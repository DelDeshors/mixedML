# -*- coding: utf-8 -*-
from typing import Literal, Optional, Any, Union
import logging as log
from abc import ABC

# Imports de base de ReservoirPy
from reservoirpy import Model, Node  # type: ignore
from reservoirpy import ESN  # type: ignore
#from reservoirpy import verbosity  # type: ignore

# joblib permet de faire tourner du code sur plusieurs coeurs du processeur en meme temps
from joblib import Parallel, delayed, cpu_count  # type: ignore

# Ici, le code tente d'importer tes propres fonctions utilitaires (qui gèrent la mise en forme des données).
# C'est souvent ici que se cachent les erreurs de "Readout" si les dimensions ne sont pas bonnes !
try:
    from .rnn_utils import (
        data_2D_to_list,
        data_list_to_2D,
        Array1D,
        Array2D,
        get_aggregator,
        get_scaler,
        aggregate_predict_output,
        fix_single_subject_predictions,
    )
except ImportError:
    # Pour import via reticulate (ajout au sys.path)
    from rnn_utils import (  # type: ignore
        data_2D_to_list,
        data_list_to_2D,
        Array1D,
        Array2D,
        get_aggregator,
        get_scaler,
        aggregate_predict_output,
        fix_single_subject_predictions,
    )

# Désactive les messages d'information de ReservoirPy dans la console pour ne pas la polluer
#verbosity(0)


class _CommonReservoirEnsemble(ABC):
    """
    Classe de base (abstraite). Elle prépare juste la tambouille interne : 
    combien de coeurs de processeur utiliser, comment mettre les données Ã  l'échelle (scaler), 
    et comment regrouper les prédictions (aggregator).
    """
    def __init__(self, seed_list, aggregator, scaler, n_procs, return_individual):
        self.aggregator = aggregator
        self._aggregator = get_aggregator(aggregator)
        self.scaler = scaler
        self._scaler = get_scaler(scaler)
        self.n_procs = self._correct_n_procs(seed_list, n_procs)
        self.return_individual = return_individual

    @staticmethod
    def _correct_n_procs(seed_list: list[int], n_procs: Optional[int] = None) -> int:
        # Sécurité : s'assure qu'on ne demande pas plus de coeurs de processeur que l'ordinateur n'en a.
        
        if (type(seed_list) == int):
          _nprocs = 1
        else:
          if n_procs is None:
            n_procs = len(seed_list)
          _nprocs = min(n_procs, len(seed_list), cpu_count() - 1)
          if _nprocs != n_procs:
              log.info("n_procs has been corrected to %d", _nprocs)
        return _nprocs

# --- LES DEUX FONCTIONS SUIVANTES SONT DES "HACKS" ---
# Pourquoi ? Quand joblib copie un modèle ReservoirPy pour l'envoyer sur un autre coeur du processeur,
# ReservoirPy panique s'il voit deux noeuds avec le même nom et ajoute "-(copy)" à  la fin.
# Le problème, c'est que ça casse la connexion entre le Réservoir et le Readout !
def _remove_copy_suffix(obj: Union[Model, Node]) -> None:
    # joblib implementation
    copysuffix = "-(copy)"
    lcopysuffix = len(copysuffix)
    name = obj.name
    if name.endswith(copysuffix):
        obj._name = name[:-lcopysuffix] # On force le retrait du suffixe pour réparer le nom


def _fix_copy_name(model: Model):
    _remove_copy_suffix(model)
    for nname in model.node_names:
        node = model.get_node(nname)
        _remove_copy_suffix(node)
# -----------------------------------------------------

def _predict_single(model: Model, X: list[Array2D], predict_controls: dict[str, Any]) -> list[Array2D]:
    """ Fonction qui sera exécutée en parallèle par chaque coeur pour faire des prédictions """
    # _fix_copy_name(model )# On répare le nom cassé par joblib
    # model.run(X) est la fonction standard de ReservoirPy pour faire une prédiction.
    # X DOIT être une liste de tableaux numpy 2D.
    return model.run(X)#, **predict_controls)


def _fit_single(model: Model, X: list[Array2D], y: list[Array2D], fit_controls: dict[str, Any]) -> Model:
    """ Fonction qui sera exécutée en parallèle par chaque coeur pour l'entrainement """
    # _fix_copy_name(model)
    # model.fit(X, y) est la fonction standard pour entrainer le Readout.
    # X et y DOIVENT avoir exactement le même nombre de séquences, et les mêmes pas de temps.
    model.fit(X, y, **fit_controls)
    return model


class JoblibReservoirEnsemble(_CommonReservoirEnsemble):
    """
    La classe principale. Elle crée plusieurs réseaux de neurones (ESN) avec des initialisations
    différentes (seeds), les entraine en même temps, et fait la moyenne de leurs prédictions.
    """
    def __init__(
        self,
        seed_list: list[int],
        esn_controls: dict[str, Any],
        fit_controls: dict[str, Any],
        predict_controls: dict[str, Any],
        aggregator: Literal["mean", "median"],
        scaler: Literal["standard", "robust", "min-max", "max-abs"],
        n_procs: Optional[int] = None,
        return_individual: Optional[bool] = None,
    ):
        super().__init__(seed_list, aggregator, scaler, n_procs, return_individual)

        # C'est ici qu'on crée les modèles. Un ESN (Echo State Network) dans ReservoirPy 
        # est un raccourci qui connecte automatiquement un noeud "Reservoir" à un noeud "Ridge" (le readout).
        # esn_controls contient les paramètres (nombre de neurones, fuite, etc.).
        if (type(seed_list) == int):
          self.model_list = ESN(**dict(**esn_controls, seed=seed_list))
          #self.model_list.reservoir.input_connectivity = 0.2
          #self.model_list.reservoir.rc_connectivity = 0.2
        else:
          self.model_list = [ESN(**dict(**esn_controls, seed=s)) for s in seed_list]
        
        # if (type(self.model_list) == list):
        #     for m in self.model_list:
        #         m.reservoir.input_connectivity = 0.2
        #         m.reservoir.rc_connectivity = 0.2
        #         #print(m.reservoir.input_connectivity)
                
        self.fit_controls = fit_controls
        self.predict_controls = predict_controls
        

    def _get_pool(self):
        # Initialise le moteur de parallèlisation (joblib)
        return Parallel(n_jobs=self.n_procs, backend="multiprocessing")

    def fit(self, X: Array2D, y: Array2D, subject_col: Array1D) -> None:
        """ Phase d'entrainement de tous les modèles """
        # 1. Mise à  l'échelle des données (ex: entre 0 et 1)
        X_scal = self._scaler.fit_transform(X)
        
        # 2. C'EST SOUVENT ICI QUE ca CASSE. 
        # data_2D_to_list doit transformer tes grosses tables de données en une LISTE de séquences.
        # Si la forme n'est pas [temps, features], ReservoirPy plantera au niveau du Readout.
        X_list = data_2D_to_list(X_scal, subject_col)
        y_list = data_2D_to_list(y, subject_col)
        
        # 3. Lancement de l'entrainement en parallèle sur plusieurs processeurs
        if (type(self.model_list) == list):
          with self._get_pool() as pool:
              self.model_list = pool(
                  delayed(_fit_single)(m, X_list, y_list, self.fit_controls)
                  for m in self.model_list
              )
        else:
          self.model_list = _fit_single(self.model_list, X_list, y_list, self.fit_controls)


    # def predict(self, X: Array2D, subject_col: Array1D) -> Array2D:
    #     """ Phase de prédiction """
    #     X_scal = self._scaler.transform(X)
    #     X_list = data_2D_to_list(X_scal, subject_col) # Transformation en liste de séquences
    #     
    #     if (type(self.model_list) == list):
    #       with self._get_pool() as pool:
    #           # Chaque modèle fait sa propre prédiction
    #           models_preds = pool(
    #               delayed(_predict_single)(m, X_list, self.predict_controls)
    #               for m in self.model_list
    #           )
    #     else:
    #       models_preds = _predict_single(self.model_list, X_list, self.predict_controls)
    #       
    #     # On répare la structure et on fait la moyenne (ou médiane) des prédictions de tous les modèles
    #     models_preds = fix_single_subject_predictions(models_preds, subject_col)
    #     if (type(self.model_list) == list):
    #       agg_pred = aggregate_predict_output(models_preds, self._aggregator)
    #     else:
    #       agg_pred = models_preds
    #     
    #     # On remet les prédictions sous forme de tableau 2D standard
    #     res = data_list_to_2D(agg_pred, subject_col)
    #     return data_list_to_2D(agg_pred, subject_col)
    
    
    def predict(self, X: Array2D, subject_col: Array1D, return_individual: bool = False) -> Array2D:
      """Phase de prédiction.
      If return_individual=False: returns the aggregated prediction as before.
      
      If return_individual=True:
        returns the prediction of each reservoir separately.
        The result is a list, one element per reservoir.
      """

      X_scal = self._scaler.transform(X)
      X_list = data_2D_to_list(X_scal, subject_col)

      if (type(self.model_list) == list):
          with self._get_pool() as pool:
              models_preds = pool(
                  delayed(_predict_single)(m, X_list, self.predict_controls)
                  for m in self.model_list
              )
      else:
          models_preds = _predict_single( self.model_list, X_list, self.predict_controls)

      # Remet chaque prédiction dans le format correspondant
      # aux sujets/observations d'origine.
      models_preds = fix_single_subject_predictions(models_preds, subject_col)

      # ---------------------------------------------------------
      # NOUVEAU : retourner les prédictions individuelles
      # ---------------------------------------------------------
      if return_individual:
        if type(self.model_list) == list:
          return [data_list_to_2D(pred, subject_col) for pred in models_preds]
        else:
          return data_list_to_2D(models_preds, subject_col)

      # ---------------------------------------------------------
      # COMPORTEMENT ACTUEL : agrégation
      # ---------------------------------------------------------
      if (type(self.model_list) == list):
        agg_pred = aggregate_predict_output(models_preds, self._aggregator)
      else:
        agg_pred = models_preds

      return data_list_to_2D(agg_pred, subject_col)
  
  
  
