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
    def __init__(self, seed_list, aggregator, scaler, n_procs):
        self.aggregator = aggregator
        self._aggregator = get_aggregator(aggregator)
        self.scaler = scaler
        self._scaler = get_scaler(scaler)
        self.n_procs = self._correct_n_procs(seed_list, n_procs)

    @staticmethod
    def _correct_n_procs(seed_list: list[int], n_procs: Optional[int] = None) -> int:
        # Sécurité : s'assure qu'on ne demande pas plus de coeurs de processeur que l'ordinateur n'en a.
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
    diffèrentes (seeds), les entraine en même temps, et fait la moyenne de leurs prédictions.
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
    ):
        super().__init__(seed_list, aggregator, scaler, n_procs)

        # C'est ici qu'on crée les modèles. Un ESN (Echo State Network) dans ReservoirPy 
        # est un raccourci qui connecte automatiquement un noeud "Reservoir" à un noeud "Ridge" (le readout).
        # esn_controls contient les paramètres (nombre de neurones, fuite, etc.).
        self.model_list = [ESN(**dict(**esn_controls, seed=s)) for s in seed_list]
        # self._model_names = [m.name for m in self.model_list]
        # self._nodes_names = [m.node_names for m in self.model_list]
        self.fit_controls = fit_controls
        self.predict_controls = predict_controls
        
    # def _fix_copy_names(self):
    #     for model in self.model_list:
    #         _fix_copy_name(model)

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
        with self._get_pool() as pool:
            self.model_list = pool(
                delayed(_fit_single)(m, X_list, y_list, self.fit_controls)
                for m in self.model_list
            )

        # self._fix_copy_names()

    def predict(self, X: Array2D, subject_col: Array1D) -> Array2D:
        """ Phase de prédiction """
        X_scal = self._scaler.transform(X)
        X_list = data_2D_to_list(X_scal, subject_col) # Transformation en liste de séquences
        
        with self._get_pool() as pool:
            # Chaque modèle fait sa propre prédiction
            models_preds = pool(
                delayed(_predict_single)(m, X_list, self.predict_controls)
                for m in self.model_list
            )

        # On répare la structure et on fait la moyenne (ou médiane) des prédictions de tous les modèles
        models_preds = fix_single_subject_predictions(models_preds, subject_col)
        agg_pred = aggregate_predict_output(models_preds, self._aggregator)
        
        # On remet les prédictions sous forme de tableau 2D standard
        res = data_list_to_2D(agg_pred, subject_col)
        return data_list_to_2D(agg_pred, subject_col)


# %% ray implementation
# !!! not updated with new rnn_utils.py module !!!


# @ray.remote
# class _ESN_Workers:

#     def __init__(
#         self,
#         X_fit: Data,
#         subject_col: NDArray,
#         seed: int,
#         esn_controls: dict[str, Any],
#         fit_controls: dict[str, Any],
#         predict_controls: dict[str, Any],
#     ):
#         self.model = ESN(**dict(**esn_controls, seed=seed))
#         self.X_fit = self.scaler.fit_transform(X_fit)
#         self.X_fit = _data_2D_to_list(self.X_fit, subject_col)
#         self.fit_controls = fit_controls
#         self.predict_controls = predict_controls

#     def fit(self, y: NDArray, subject_col: NDArray) -> None:
#         y = _data_2D_to_list(y, subject_col)
#         self.model.fit(self.X_fit, y, **self.fit_controls)

#     def predict(
#         self, X_pred: NDArray = None, subject_col: NDArray = None
#     ) -> list[NDArray]:
#         if X_pred is None:
#             X_pred = self.X_fit
#         else:
#             X_pred = self.scaler.transform(X_pred)
#         X_pred = _data_2D_to_list(X_pred, subject_col)
#         return self.model.run(X_pred, **self.predict_controls)


# class RayReservoirEnsemble(_CommonReservoirEnsemble):

#     def __init__(
#         self,
#         X_fit: Data,
#         seed_list: list[int],
#         esn_controls: dict[str, Any],
#         fit_controls: dict[str, Any],
#         predict_controls: dict[str, Any],
#         aggregator: Literal["mean", "median"],
#         scaler: Literal["standard", "robust", "min-max", "max-abs"],
#         n_procs: Optional[int] = None,
#     ):
#         super().__init__(aggregator, scaler)
#         _nprocs = self._correct_n_procs(seed_list, n_procs)
#         ray.init(num_cpus=_nprocs)
#         self.workers_list = [
#             _ESN_Workers.remote(  # type:ignore
#                 X_fit, s, esn_controls, fit_controls, predict_controls
#             )
#             for s in seed_list
#         ]

#     def fit(self, y: Data) -> None:
#         futures = [w.fit.remote(y) for w in self.workers_list]
#         _ = ray.get(futures)

#     def predict(self, X: Data = None) -> list[Data]:

#         futures = [w.predict.remote(X) for w in self.workers_list]
#         models_preds = ray.get(futures)
#         return self._convert_predict_output(models_preds)
