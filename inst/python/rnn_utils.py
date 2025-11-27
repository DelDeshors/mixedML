from typing import Callable, Union
from numpy import unique, zeros, all as npall, mean, median, stack
from numpy.typing import NDArray
from sklearn.preprocessing import (  # type: ignore
    StandardScaler,
    RobustScaler,
    MinMaxScaler,
    MaxAbsScaler,
)

Array1D = NDArray
Array2D = NDArray
Scaler = Union[StandardScaler, RobustScaler, MinMaxScaler, MaxAbsScaler]


# !!! IMPORTANT !!!
# do not use lambda in order to be able to save the model with joblib


def data_2D_to_list(data_2D: Array2D, subject_col: Array1D) -> list[Array2D]:
    assert data_2D.ndim == 2
    assert subject_col.ndim == 1
    assert data_2D.shape[0] == len(subject_col)
    return [data_2D[subject_col == sub] for sub in unique(subject_col)]


def data_list_to_2D(data_list: list[Array2D], subject_col: Array1D) -> Array2D:
    subz = unique(subject_col)
    assert len(data_list) == len(subz)
    data2D = zeros((len(subject_col), data_list[0].shape[1]))
    for isub, sub in enumerate(subz):
        assert npall(data2D[subject_col == sub] == 0)
        data2D[subject_col == sub] = data_list[isub]
    return data2D  # -*- coding: utf-8 -*-


def mean_axis_0(x):
    return mean(x, axis=0)


def median_axis_0(x):
    return median(x, axis=0)


def get_aggregator(aggregator: str) -> Callable[[list[Array2D]], Array2D]:
    funcs: dict[str, Callable[[list[Array2D]], Array2D]] = {
        "mean": mean_axis_0,
        "median": median_axis_0,
    }
    try:
        return funcs[aggregator]
    except KeyError:
        raise ValueError(f"aggregator must be one of {funcs.keys()}")


def get_scaler(scaler: str) -> Scaler:
    funcs: dict[str, Scaler] = {
        "standard": StandardScaler(),
        "robust": RobustScaler(),
        "min-max": MinMaxScaler(),
        "max-abs": MaxAbsScaler(),
    }
    try:
        return funcs[scaler]
    except KeyError:
        raise ValueError(f"scaler must be one of {funcs.keys()}")


def aggregate_predict_output(
    models_preds: list[list[Array2D]],
    aggregator: Callable[[list[Array2D]], Array2D],
) -> list[Array2D]:
    N_series = len(models_preds[0])
    agg_pred = [
        aggregator([mpred[serie] for mpred in models_preds])
        for serie in range(N_series)
    ]
    return agg_pred


def fix_single_subject_predictions(
    models_preds: list[list[Array2D]], subject_col: Array1D
) -> list[list[Array2D]]:
    if len(unique(subject_col)) == 1:
        # this case is problematic since reservoir has a "funny" (haha) output
        for i, mpred in enumerate(models_preds):
            models_preds[i] = [stack(mpred)]
    return models_preds
