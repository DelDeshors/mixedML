# -*- coding: utf-8 -*-
from numpy import ndarray
from reservoirpy.datasets import mackey_glass, japanese_vowels  # type: ignore


from inst.python.reservoir_ensemble import (
    JoblibReservoirEnsemble,
    RayReservoirEnsemble,
)


data = mackey_glass(2000)

Xarr, yarr = data[:50], data[1:51]

Xlst, Ylst, _, _ = japanese_vowels(repeat_targets=True)

seed_list = [1, 2, 3]
esn_controls = {"units": 5, "ridge": 1e-5}
n_procs = 5
agg_func = "median"
seed_list = [1, 2, 3]
fit_controls = {"reset": True, "stateful": True, "warmup": 2}
predict_controls = {"reset": True, "stateful": True}


def pred_same_shape(a, b) -> bool:
    if isinstance(a, list) and isinstance(b, list):
        return all(a_.shape == b_.shape for a_, b_ in zip(a, b))
    elif isinstance(a, ndarray) and isinstance(b, ndarray):
        return a.shape == b.shape
    raise UserWarning()


def train_fit_joblib_reservoir_ensemble(n_procs, X, y):
    resmod = JoblibReservoirEnsemble(
        seed_list=seed_list,
        esn_controls=esn_controls,
        fit_controls=fit_controls,
        predict_controls=predict_controls,
        n_procs=n_procs,
        agg_func="mean",
    )
    resmod.fit(X, y)
    ypred = resmod.predict(X)
    assert pred_same_shape(ypred, y)


def test_joblib_reservoir_ensemble():
    train_fit_joblib_reservoir_ensemble(1, Xarr, yarr)
    train_fit_joblib_reservoir_ensemble(5, Xarr, yarr)
    train_fit_joblib_reservoir_ensemble(10, Xlst, Ylst)


def test_ray_reservoir_workers():

    model = RayReservoirEnsemble(
        Xlst,
        seed_list,
        esn_controls,
        fit_controls,
        predict_controls,
        agg_func,
        n_procs,
    )

    model.fit(Ylst)
