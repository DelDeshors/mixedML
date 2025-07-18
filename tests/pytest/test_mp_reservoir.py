# -*- coding: utf-8 -*-

# !!! fixtures defined in conftest.py

from numpy import ndarray
import joblib


from inst.python.reservoir_ensemble import (
    JoblibReservoirEnsemble,
    # RayReservoirEnsemble,
)


seed_list = [1, 2, 3]
esn_controls = {"units": 5, "ridge": 1e-5}
n_procs = 2
aggregator = "median"
scaler = "standard"
seed_list = [1, 2, 3]
fit_controls = {"reset": True, "stateful": True, "warmup": 0}
predict_controls = {"reset": True, "stateful": True}


def pred_same_shape(a, b) -> bool:
    if isinstance(a, list) and isinstance(b, list):
        return all(a_.shape == b_.shape for a_, b_ in zip(a, b))
    elif isinstance(a, ndarray) and isinstance(b, ndarray):
        return a.shape == b.shape
    raise UserWarning()


def test_train_predict_joblib_reservoir_ensemble(data_2D_x, data_2D_y, subject):
    resmod = JoblibReservoirEnsemble(
        seed_list=seed_list,
        esn_controls=esn_controls,
        fit_controls=fit_controls,
        predict_controls=predict_controls,
        n_procs=n_procs,
        scaler=scaler,
        aggregator=aggregator,
    )
    resmod.fit(X=data_2D_x, y=data_2D_y, subject_col=subject)
    ypred = resmod.predict(data_2D_x, subject_col=subject)
    assert ypred.shape == data_2D_y.shape


def test_create_backup(tmp_path):
    resmod = JoblibReservoirEnsemble(
        seed_list=seed_list,
        esn_controls=esn_controls,
        fit_controls=fit_controls,
        predict_controls=predict_controls,
        n_procs=n_procs,
        scaler=scaler,
        aggregator=aggregator,
    )
    joblib.dump(resmod, tmp_path / "test.joblib")
