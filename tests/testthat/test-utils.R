spec_formula <- Y ~ X1 + X2 + X3 + X1 * X4

test_that(".get_y_label", {
  expect_equal(.get_y_label(spec_formula), "Y")
})

test_that(".get_x_labels", {
  expect_equal(.get_x_labels(spec_formula), c("X1", "X2", "X3", "X4"))
})
