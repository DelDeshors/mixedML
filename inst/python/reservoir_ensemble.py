# -*- coding: utf-8 -*-
from typing import Literal, Optional, Any, Union
import logging as log
from abc import ABC, abstractproperty


from numpy import mean, median, ndarray
from reservoirpy import Model, Node  # type: ignore
from reservoirpy.nodes import ESN  # type: ignore
from reservoirpy import verbosity  # type: ignore
from reservoirpy.type import Data  # type: ignore
import ray
from joblib import Parallel, delayed, cpu_count  # type: ignore

verbosity(0)


# %% common (joblib/ray) implementation


class _CommonReservoirEnsemble(ABC):

    @property
    def agg_func(self):
        return self._agg_func

    @agg_func.setter
    def agg_func(self, value):
        agg_funcs = {
            "mean": lambda x: mean(x, axis=0),
            "median": lambda x: median(x, axis=0),
        }
        try:
            self._agg_func = agg_funcs[value]
        except KeyError:
            raise ValueError(f"agg_func must be one of {agg_funcs.keys()}")

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

    def _convert_predict_output(self, models_preds: list[Data]) -> list[Data]:

        def uniformize(mpred: Data) -> list[ndarray]:
            if isinstance(mpred, list):
                return mpred
            if isinstance(mpred, ndarray):
                return [mpred]
            raise TypeError

        models_preds = [uniformize(mpred) for mpred in models_preds]
        # list(Models) > list(Series) > array(Timesteps x Features)
        mod1_pred = models_preds[0]
        N_series = len(mod1_pred)

        agg_pred = [
            self.agg_func([mpred[serie] for mpred in models_preds])
            for serie in range(N_series)
        ]

        if len(agg_pred) == 1:
            agg_pred = agg_pred[0]

        return agg_pred


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


def _predict_single(model: Model, X: Data, predict_controls: dict[str, Any]) -> Data:
    _fix_copy_name(model)
    return model.run(X, **predict_controls)


def _fit_single(model: Model, X: Data, y: Data, fit_controls: dict[str, Any]) -> Model:
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
        agg_func: Literal["mean", "median"],
        n_procs: Optional[int] = None,
    ):
        self.agg_func = agg_func
        self.model_list = [ESN(**dict(**esn_controls, seed=s)) for s in seed_list]
        self._model_names = [m.name for m in self.model_list]
        self._nodes_names = [m.node_names for m in self.model_list]
        _nprocs = self._correct_n_procs(seed_list, n_procs)
        self.pool_open(_nprocs)
        self.fit_controls = fit_controls
        self.predict_controls = predict_controls

    def pool_open(self, n_procs: int):
        # https://joblib.readthedocs.io/en/stable/parallel.html
        # backend="loky" does not work when using reticulate
        # it seems quite hard to understand why, and the fact that another
        # backend works suggest that it is not a coding problem
        self._pool = Parallel(n_jobs=n_procs, backend="multiprocessing")

    def pool_close(self):
        self._pool.close()

    @staticmethod
    def _get_agg_func(agg_func):
        agg_funcs = {
            "mean": lambda x: mean(x, axis=0),
            "median": lambda x: median(x, axis=0),
        }
        try:
            return agg_funcs[agg_func]
        except KeyError:
            raise ValueError(f"agg_func must be one of {agg_funcs.keys()}")

    def _fix_copy_names(self):
        for model in self.model_list:
            _fix_copy_name(model)

    def fit(self, X: Data, y: Data) -> None:
        self.model_list = self._pool(
            delayed(_fit_single)(m, X, y, self.fit_controls) for m in self.model_list
        )
        self._fix_copy_names()

    def predict(self, X: Data) -> list[Data]:
        models_preds = self._pool(
            delayed(_predict_single)(m, X, self.predict_controls)
            for m in self.model_list
        )
        return self._convert_predict_output(models_preds)


# %% ray implementation


@ray.remote
class _ESN_Workers:

    def __init__(
        self,
        X_fit: Data,
        seed: int,
        esn_controls: dict[str, Any],
        fit_controls: dict[str, Any],
        predict_controls: dict[str, Any],
    ):
        self.model = ESN(**dict(**esn_controls, seed=seed))
        self.X_fit = X_fit
        self.fit_controls = fit_controls
        self.predict_controls = predict_controls

    def fit(self, y: Data) -> None:
        self.model.fit(self.X_fit, y, **self.fit_controls)

    def predict(self, X_pred: Data = None) -> Data:
        if X_pred is None:
            X_pred = self.X_fit
        return self.model.run(X_pred, **self.predict_controls)


class RayReservoirEnsemble(_CommonReservoirEnsemble):

    def __init__(
        self,
        X_fit: Data,
        seed_list: list[int],
        esn_controls: dict[str, Any],
        fit_controls: dict[str, Any],
        predict_controls: dict[str, Any],
        agg_func: Literal["mean", "median"],
        n_procs: Optional[int] = None,
    ):
        self.agg_func = agg_func
        _nprocs = self._correct_n_procs(seed_list, n_procs)
        ray.init(num_cpus=_nprocs)
        self.workers_list = [
            _ESN_Workers.remote(  # type:ignore
                X_fit, s, esn_controls, fit_controls, predict_controls
            )
            for s in seed_list
        ]

    def fit(self, y: Data) -> None:
        futures = [w.fit.remote(y) for w in self.workers_list]
        _ = ray.get(futures)

    def predict(self, X: Data = None) -> list[Data]:

        futures = [w.predict.remote(X) for w in self.workers_list]
        models_preds = ray.get(futures)
        return self._convert_predict_output(models_preds)
