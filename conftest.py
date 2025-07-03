import pytest
import numpy as np


@pytest.fixture
def data_2D_x():
    return np.array(
        [
            [2.0, 2.0, 2.0],
            [3.0, 3.0, 3.0],
            [1.0, 1.0, 1.0],
            [3.0, 3.0, 3.0],
            [2.0, 2.0, 2.0],
            [3.0, 3.0, 3.0],
        ]
    )


@pytest.fixture
def data_2D_y():
    return np.array(
        [
            [2.0, 2.0],
            [3.0, 3.0],
            [1.0, 1.0],
            [3.0, 3.0],
            [2.0, 2.0],
            [3.0, 3.0],
        ]
    )


@pytest.fixture
def subject():
    return np.array([5, 10, 3, 10, 5, 10])


@pytest.fixture
def data_list_x():
    x1 = np.ones((1, 3)) * 1
    x2 = np.ones((2, 3)) * 2
    x3 = np.ones((3, 3)) * 3
    return [x1, x2, x3]
