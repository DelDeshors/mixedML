# -*- coding: utf-8 -*-

# !!! fixtures defined in conftest.py

from inst.python.rnn_utils import data_2D_to_list, data_list_to_2D

import numpy as np


def test_data_2D_to_list(data_2D_x, subject, data_list_x):
    new = data_2D_to_list(data_2D_x, subject)
    assert all(np.array_equal(a, b) for a, b in zip(data_list_x, new))


def test_data_list_to_2D(data_2D_x, subject, data_list_x):
    new = data_list_to_2D(data_list_x, subject)
    assert np.array_equal(data_2D_x, new)
