# -*- coding: utf-8 -*-
from typing import Literal, Optional, Any, Union
import logging as log
from abc import ABC


from reservoirpy import Model, Node  # type: ignore
from reservoirpy.nodes import ESN  # type: ignore
from reservoirpy import verbosity  # type: ignore

# import ray
from joblib import Parallel, delayed, cpu_count  # type: ignore


try:
    # Pour exécution avec pytest (en tant que package)
    from .rnn_utils import (
        data_2D_to_list,
        data_list_to_2D,
        Array1D,
        Array2D,
        get_aggregator,
        get_scaler,
        aggregate_predict_output,
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
    )


verbosity(0)


# %% common (joblib/ray) implementation


class _CommonReservoirEnsemble(ABC):

    def __init__(self, seed_list, aggregator, scaler, n_procs):
        self.aggregator = aggregator
        self._aggregator = get_aggregator(aggregator)
        self.scaler = scaler
        self._scaler = get_scaler(scaler)
        self.n_procs = self._correct_n_procs(seed_list, n_procs)

    @staticmethod
    def _correct_n_procs(
        seed_list: list[int],
        n_procs: Optional[int] = None,
    ) -> int:
        if n_procs is None:
            n_procs = len(seed_list)
        _nprocs = min(n_procs, len(seed_list), cpu_count() - 1)
        if _nprocs != n_procs:
            log.info("n_procs has been corrected to %d", _nprocs)
        return _nprocs


# %% joblib implementation
def _remove_copy_suffix(obj: Union[Model, Node]) -> None:
    copysuffix = "-(copy)"
    lcopysuffix = len(copysuffix)
    name = obj.name
    if name.endswith(copysuffix):
        obj._name = name[:-lcopysuffix]


def _fix_copy_name(model: Model):
    _remove_copy_suffix(model)
    for nname in model.node_names:
        node = model.get_node(nname)
        _remove_copy_suffix(node)


def _predict_single(
    model: Model, X: list[Array2D], predict_controls: dict[str, Any]
) -> list[Array2D]:
    _fix_copy_name(model)
    return model.run(X, **predict_controls)


def _fit_single(
    model: Model,
    X: list[Array2D],
    y: list[Array2D],
    fit_controls: dict[str, Any],
) -> Model:
    _fix_copy_name(model)
    model.fit(X, y, **fit_controls)
    return model


class JoblibReservoirEnsemble(_CommonReservoirEnsemble):

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
        self.model_list = [ESN(**dict(**esn_controls, seed=s)) for s in seed_list]
        self._model_names = [m.name for m in self.model_list]
        self._nodes_names = [m.node_names for m in self.model_list]
        self._pool_open(self.n_procs)
        self.fit_controls = fit_controls
        self.predict_controls = predict_controls

    def _pool_open(self, n_procs: int):
        # https://joblib.readthedocs.io/en/stable/parallel.html
        # backend="loky" does not work when using reticulate
        # it seems quite hard to understand why, and the fact that another
        # backend works suggest that it is not a coding problem
        self._pool = Parallel(n_jobs=n_procs, backend="multiprocessing")

    def _pool_close(self):
        self._pool.close()

    def _fix_copy_names(self):
        for model in self.model_list:
            _fix_copy_name(model)

    def fit(self, X: Array2D, y: Array2D, subject_col: Array1D) -> None:
        X_scal = self._scaler.fit_transform(X)
        X_list = data_2D_to_list(X_scal, subject_col)
        y_list = data_2D_to_list(y, subject_col)
        self.model_list = self._pool(
            delayed(_fit_single)(m, X_list, y_list, self.fit_controls)
            for m in self.model_list
        )
        self._fix_copy_names()

    def predict(self, X: Array2D, subject_col: Array1D) -> Array2D:
        X_scal = self._scaler.transform(X)
        X_list = data_2D_to_list(X_scal, subject_col)
        models_preds = self._pool(
            delayed(_predict_single)(m, X_list, self.predict_controls)
            for m in self.model_list
        )
        agg_pred = aggregate_predict_output(models_preds, self._aggregator)
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
