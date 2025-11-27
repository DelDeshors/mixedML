
- [1 Introduction](#1-introduction)
- [2 Method](#2-method)
- [3 Example dataset](#3-example-dataset)
- [4 Main/fit functions](#4-mainfit-functions)
  - [4.1 Formalism](#41-formalism)
  - [4.2 Arguments](#42-arguments)
  - [4.3 Example](#43-example)
- [5 Model attributes](#5-model-attributes)
- [6 Post-fit functions](#6-post-fit-functions)
  - [6.1 `summary`](#61-summary)
  - [6.2 `plot_convergence`](#62-plot_convergence)
  - [6.3 `plot_prediction_check`](#63-plot_prediction_check)
  - [6.4 `predict`](#64-predict)
  - [6.5 `plot_predictions`](#65-plot_predictions)
  - [6.6 `save_mixedml`](#66-save_mixedml)
  - [6.7 `load_mixedml`](#67-load_mixedml)
- [7 Remark on logging](#7-remark-on-logging)
- [8 Working with Python](#8-working-with-python)
  - [8.1 Let `reticulate` handles the
    installation](#81-let-reticulate-handles-the-installation)
  - [8.2 Use `reticulate` with a user controlled
    environement](#82-use-reticulate-with-a-user-controlled-environement)
    - [8.2.1 Installation](#821-installation)
    - [8.2.2 Setup of the `RETICULATE_PYTHON_ENV` environment
      variable](#822-setup-of-the-reticulate_python_env-environment-variable)
  - [8.3 Note to devs](#83-note-to-devs)

# 1 Introduction

This package provides functions to train hybrid mixed effects models.
Such models are a variation of linear mixed effects models, used for
Gaussian longitudinal data, whose formulation is:

$$Y_{ij} = X_{ij} \beta +  Z_{ij} u_i + w_{i} + \varepsilon_{ij}$$

… where:

- $i$ is the subject,
- $j$ is the observation,
- $\beta$ is the vector of fixed effects and $X_{ij}$ is associated
  covariates,
- $u_i$ is the vector of random effects and $Z_{ij}$ the associated
  covariates,
- $w_i$ is a zero-mean Gaussian stochastic process (such as Brownian
  motion) modeling the correlation in the individual error,
- $\epsilon_{ij}$ is the zero-mean Gaussian residual error.
- 

For such hybrid models:

- a Machine Leaning (ML) model is used to estimates the fixed effects;
- a Mixed Effects model (`hlme` from [lcmm
  package](https://cecileproust-lima.github.io/lcmm/articles/lcmm.html))
  is constrained to estimate only random effects.

That is, the formulation becomes:

$$Y_{ij} = f_{ML}(X_{ij}) +  Z_{ij} u_i + w_{i} + \varepsilon_{ij}$$

… where $f_{ML}(X_{ij})$ is the output from a ML model trained to
predict the fixed effects.

Using ML models to estimates the fixed effects has two main advantages
comparing to linear models:

- they can handle highly non-linear relations, and do so with simple
  inputs (instead of being highly dependent of the specification);
- they can handle complex time interactions, in the case of Recurrent
  Neural Networks;

However, some ML models have a “black box” effect, as one cannot use its
estimated parameters to understand the relations within the data.

# 2 Method

The method uses a iterative training of both fixed effects and random
effects models.

So far we are fitting each model on the **residuals** of the other. This
is only valid for **regression problems** where

- in generalized linear model terms: the models use an identity link,
- in neural networks terms: the models do not use a final activation
  function.

In such case, fitting on the residuals is equivalent to fitting using
the predictions (of the other model) as offset.

The pseudo-code is as follow (`fe`/`re` stands for fixed/random
effects):

    ml_model_fe <- initiate_ml_model_fe()
    hlme_model_re <- initiate_hlme_model_re()

    Yre <- 0.
    while not converged:
      fit ml_model_fe on X and (Y - Yre)
      Yfe <-  ml_model_fe(X)

      fit hlme_model_re on X and (Y - Yfe)
      Yre <-  hlme_model_re(X)

      converged <- criterion(Y, Yfe+Yre)

This method works with any kind of model, so far models coded in R and
Python acn be easily implemented.

# 3 Example dataset

The dataset `data_mixedml` is proposed. It is generated using the
`R/data_gen.R` file.

It is a synthetic longitudinal dataset, containing data for 10 subjects
on 5 regularly spaced time steps. It contains two response columns for
both fixed and mixed effects. NA values have been added manually, and
some observations are deleted. Also the row names have been shuffled in
order to enforce a clear use of row names or indices in the code.

``` r
data_mixedml
#>    ID time    x1    x2 x3    yf     yr    ym ym_nonoise
#> 39  1    0    NA 100.6  1 206.9 -12.76 194.5      194.2
#> 35  1    1 11.01 103.5  1 217.9 -13.29 205.0      204.6
#> 10  1    2  9.82  97.9  1 197.3 -12.29 184.7      185.0
#> 1   1    3 11.01  98.2  1 215.3 -12.88 201.8      202.4
#> 42  1    4  8.89  98.5  1 183.6 -11.89 171.5      171.7
#> 49  2    0 10.38  97.5  0 101.7  10.97 112.8      112.6
#> 19  2    1  9.35    NA  0  97.4  11.28 108.6      108.7
#> 43  2    2  9.60  97.7  0  97.8  11.06 107.3      108.9
#> 6   2    3  9.10 102.2  0  97.6  11.66 108.6      109.3
#> 18  2    4  9.98 103.8  0 102.8  11.79 115.1      114.6
#> 25  3    0 11.08  97.0  1 215.6  13.11    NA      228.7
#> 33  3    1  9.11  97.3  1 186.4  11.92 197.6      198.3
#> 37  3    2 10.43  96.0  1 205.5  12.65 218.5      218.2
#> 2   3    3  9.14 105.8  1 191.0  12.48 204.2      203.5
#> 31  3    4 10.07 102.0  1 203.0  12.81 216.1      215.8
#> 16  4    0  9.96  98.8  0 100.2   3.43 103.1      103.6
#> 15  4    1 10.43 100.6  0 103.4   3.29    NA      106.7
#> 26  4    2 10.17 101.2  0 102.5   3.53 106.8      106.0
#> 13  4    3  9.71 104.9  0 102.0   4.23 106.3      106.2
#> 34  4    4 10.39  99.8  0 102.9   3.24 106.2      106.1
#> 23  5    1  9.41  99.6  1 191.9  -3.72 187.2      188.2
#> 22  5    2 10.63 102.1  1 211.6  -3.97 207.5      207.6
#> 11  5    3  9.84 100.6  1 198.9  -3.81 195.1      195.1
#> 50  5    4 10.02  96.3  1 199.4  -3.74 194.8      195.6
#> 46  6    0  9.26  99.8  0  97.2  16.39 113.9      113.6
#> 7   6    2  9.12  91.2  0  92.2  15.33 108.3      107.5
#> 40  6    3  9.47  98.1  0  97.4  16.31 114.1      113.7
#> 44  6    4  9.33  98.3  0  96.8  16.26 112.6      113.1
#> 28  7    0 10.38 104.5  1 208.9  -6.09 202.7      202.8
#> 38  7    1  9.68 102.7  1 197.5  -5.55 192.6      192.0
#> 4   7    2 10.72  99.0  1 211.2  -6.52 204.5      204.7
#> 14  7    3  9.69  96.1  1 194.4  -5.73 189.8      188.7
#> 24  7    4 10.11 100.0  1 202.7  -5.99 196.1      196.7
#> 9   8    0 10.13 103.0  0 103.2  -7.37  96.1       95.8
#> 17  8    1 10.21 101.2  0 102.7  -7.30  94.6       95.4
#> 32  8    2  9.26 104.3  0  99.4  -7.24  92.9       92.2
#> 45  8    3 10.09 100.4  0 101.7  -7.23  94.8       94.4
#> 30  8    4 11.03  96.0  0 104.1  -7.22  96.6       96.9
#> 12  9    0 10.36  98.5  1 205.7   2.49 208.0      208.2
#> 48  9    1  9.76  97.3  1 196.0   2.51 198.4      198.5
#> 36  9    2  9.76 101.0  1 197.8   2.64 201.2      200.5
#> 29  9    3 10.92 100.9  1 215.3   2.51 217.7      217.8
#> 5   9    4 10.26  96.9  1 203.3   2.44 205.5      205.7
#> 47 10    0  9.44 101.2  0  98.8 -21.28  77.2       77.5
#> 8  10    1  9.84 102.4  0 101.4 -21.84  79.4       79.6
#> 20 10    2 10.05  98.3  0 100.4 -21.58  77.4       78.8
#> 3  10    3 10.32 100.5  0 102.9 -22.11  81.6       80.8
#> 41 10    4 10.19 100.1  0 102.0 -21.93  80.2       80.1
```

# 4 Main/fit functions

## 4.1 Formalism

The MixedML models are obtained using specific functions which have for
signature:

``` r
XXXX_mixedml(
  # parameters of the MixedML model (inpired by the hlme function definition)
  fixed_spec,
  random_spec,
  data_,
  subject,
  time,
  # parameters for MixedML method
  mixedml_controls,
  # controls (extra-parameters) for the hlme model
  hlme_controls,
  # controls (extra-parameters) specific to the implemented ML model
  controls_1, controls_2, et_caetera
)
```

… where `XXXX` takes the name of the ML model used for the fixed
effects. As an example, the Reservoir Computing model is named
`reservoir_mixedml`.

Using a dedicated function allows to benefit from the code-completion
since every arguments is explicitely specified (no optional arguments).

## 4.2 Arguments

The `fixed_spec`, `random_spec`, `cor`, `data`, `subject` and `time` are
used by both sub-models and are taken from the `hlme` function which can
be seen in [the lcmm package
documentation](https://cecileproust-lima.github.io/lcmm/reference/hlme.html)

Then several controls are defined, using specific functions whose names
correspond to the control names. That is, the `some_name_ctrls(…)`
function is used to define `some_name_controls` controls. Each control
has its specific help.

## 4.3 Example

Here is an example using the `reservoir_mixedml` function (here is the
[corresponding vignette](mixedML_reservoir.html)):

``` r
data_train <- data_mixedml[data_mixedml$ID < 9, ]
data_val <- data_mixedml[data_mixedml$ID == 9, ]
data_test <- data_mixedml[data_mixedml$ID == 10, ]

model_reservoir <- reservoir_mixedml(
  fixed_spec = ym ~ 1 + x1 + x2 + x3,
  random_spec = ~ 1 + x1 + x2,
  data = data_train,
  data_val = data_val,
  subject = "ID",
  time = "time",
  # parameters for MixedML method
  mixedml_controls = mixedml_ctrls(
    earlystopping_controls = earlystopping_ctrls(min_mse_gain = 0.1, patience = 10),
    all_info_hlme_prediction = TRUE
  ),
  # controls (extra-parameters) for the hlme model
  hlme_controls = hlme_ctrls(maxiter = 50, idiag = TRUE),
  # controls (extra-parameters) for the ML model
  esn_controls = esn_ctrls(units = 20, ridge = 1e-5),
  ensemble_controls = ensemble_ctrls(seed_list = c(1, 2, 3, 4, 5)),
  fit_controls = fit_ctrls(warmup = 1)
)
#> Warning in .check_na_combinaison(data_train, fixed_spec, random_spec, target_name): 
#>          2 incomplete cases for the ML models
#>          4 incomplete cases for the HLME model
#>          2 NA values in target
#>          => 4/38 observations could not be used to train (either no fixed preds, random preds or target).
#> step#1
#>  fitting fixed effects...
#>  fitting random effects...
#>  MSE-train = 85.38
#>  MSE-val = 48.3
#>  (saving best model)
#>  (improvement)
#> step#2
#>  fitting fixed effects...
#>  fitting random effects...
#>  MSE-train = 77.51
#>  MSE-val = 30.28
#>  (saving best model)
#>  (improvement)
#> step#3
#>  fitting fixed effects...
#>  fitting random effects...
#>  MSE-train = 70.84
#>  MSE-val = 20.54
#>  (saving best model)
#>  (improvement)
#> step#4
#>  fitting fixed effects...
#>  fitting random effects...
#>  MSE-train = 59.75
#>  MSE-val = 17.4
#>  (saving best model)
#>  (improvement)
#> step#5
#>  fitting fixed effects...
#>  fitting random effects...
#>  MSE-train = 49
#>  MSE-val = 15.6
#>  (saving best model)
#>  (improvement)
#> step#6
#>  fitting fixed effects...
#>  fitting random effects...
#>  MSE-train = 44.6
#>  MSE-val = 14.93
#>  (saving best model)
#>  (improvement)
#> step#7
#>  fitting fixed effects...
#>  fitting random effects...
#>  MSE-train = 40.23
#>  MSE-val = 14.17
#>  (saving best model)
#>  (improvement)
#> step#8
#>  fitting fixed effects...
#>  fitting random effects...
#>  MSE-train = 37.03
#>  MSE-val = 13.54
#>  (saving best model)
#>  (improvement)
#> step#9
#>  fitting fixed effects...
#>  fitting random effects...
#>  MSE-train = 33.69
#>  MSE-val = 12.65
#>  (saving best model)
#>  (improvement)
#> step#10
#>  fitting fixed effects...
#>  fitting random effects...
#>  MSE-train = 30.91
#>  MSE-val = 11.87
#>  (saving best model)
#>  (improvement)
#> step#11
#>  fitting fixed effects...
#>  fitting random effects...
#>  MSE-train = 27.85
#>  MSE-val = 10.86
#>  (saving best model)
#>  (improvement)
#> step#12
#>  fitting fixed effects...
#>  fitting random effects...
#>  MSE-train = 25.07
#>  MSE-val = 9.83
#>  (saving best model)
#>  (improvement)
#> step#13
#>  fitting fixed effects...
#>  fitting random effects...
#>  MSE-train = 22.28
#>  MSE-val = 8.725
#>  (saving best model)
#>  (improvement)
#> step#14
#>  fitting fixed effects...
#>  fitting random effects...
#>  MSE-train = 19.3
#>  MSE-val = 7.703
#>  (saving best model)
#>  (improvement)
#> step#15
#>  fitting fixed effects...
#>  fitting random effects...
#>  MSE-train = 16.74
#>  MSE-val = 6.637
#>  (saving best model)
#>  (improvement)
#> step#16
#>  fitting fixed effects...
#>  fitting random effects...
#>  MSE-train = 14.05
#>  MSE-val = 5.449
#>  (saving best model)
#>  (improvement)
#> step#17
#>  fitting fixed effects...
#>  fitting random effects...
#>  MSE-train = 11.5
#>  MSE-val = 4.302
#>  (saving best model)
#>  (improvement)
#> step#18
#>  fitting fixed effects...
#>  fitting random effects...
#>  MSE-train = 8.912
#>  MSE-val = 3.117
#>  (saving best model)
#>  (improvement)
#> step#19
#>  fitting fixed effects...
#>  fitting random effects...
#>  MSE-train = 6.313
#>  MSE-val = 1.937
#>  (saving best model)
#>  (improvement)
#> step#20
#>  fitting fixed effects...
#>  fitting random effects...
#>  MSE-train = 3.57
#>  MSE-val = 1.103
#>  (saving best model)
#>  (improvement)
#> step#21
#>  fitting fixed effects...
#>  fitting random effects...
#>  MSE-train = 2.736
#>  MSE-val = 1.096
#>  (saving best model)
#>  (no improvement #1)
#> step#22
#>  fitting fixed effects...
#>  fitting random effects...
#>  MSE-train = 4.699
#>  MSE-val = 1.207
#>  (no improvement #2)
#> step#23
#>  fitting fixed effects...
#>  fitting random effects...
#>  MSE-train = 6.087
#>  MSE-val = 1.101
#>  (no improvement #3)
#> step#24
#>  fitting fixed effects...
#>  fitting random effects...
#>  MSE-train = 7.583
#>  MSE-val = 1.051
#>  (saving best model)
#>  (no improvement #4)
#> step#25
#>  fitting fixed effects...
#>  fitting random effects...
#>  MSE-train = 8.396
#>  MSE-val = 1.102
#>  (no improvement #5)
#> step#26
#>  fitting fixed effects...
#>  fitting random effects...
#>  MSE-train = 7.41
#>  MSE-val = 1.254
#>  (no improvement #6)
#> step#27
#>  fitting fixed effects...
#>  fitting random effects...
#>  MSE-train = 5.943
#>  MSE-val = 1.45
#>  (no improvement #7)
#> step#28
#>  fitting fixed effects...
#>  fitting random effects...
#>  MSE-train = 5.273
#>  MSE-val = 1.72
#>  (no improvement #8)
#> step#29
#>  fitting fixed effects...
#>  fitting random effects...
#>  MSE-train = 5.097
#>  MSE-val = 1.903
#>  (no improvement #9)
#> step#30
#>  fitting fixed effects...
#>  fitting random effects...
#>  MSE-train = 4.891
#>  MSE-val = 2.022
#>  (no improvement #10)
#> Warning in mixedml_training_loop(fixed_model, fixed_spec, random_spec, data, :
#> Conditions defined in early_stopping: aborting training loop!
#> Final convergence of HLME with strict convergence criterions.
```

The resulting model will be used in the remaining sections.

# 5 Model attributes

Each sub-models are accessible from the fitted MixedML model:

``` r
model_reservoir$random_model
#> Heterogenous linear mixed model 
#>      fitted by maximum likelihood method 
#>  
#> hlme(fixed = ym ~ 1, random = ~1 + x1 + x2, subject = "ID", idiag = TRUE, 
#>     cor = NULL, data = data, convB = 1e-04, convL = 1e-04, convG = 1e-04, 
#>     maxiter = 50, na.action = 1, posfix = 1, verbose = FALSE, 
#>     var.time = "time", nproc = 1)
#>  
#> Statistical Model: 
#>      Dataset: data 
#>      Number of subjects: 8 
#>      Number of observations: 34 
#>      Number of observations deleted: 4 
#>      Number of latent classes: 1 
#>      Number of parameters: 5  
#>      Number of estimated parameters: 4  
#>  
#> Iteration process: 
#>      Convergence criteria satisfied 
#>      Number of iterations:  1 
#>      Convergence criteria: parameters= 1.3e-09 
#>                          : likelihood= 7.4e-09 
#>                          : second derivatives= 1.7e-10 
#>  
#> Goodness-of-fit statistics: 
#>      maximum log-likelihood: -113.25  
#>      AIC: 234.5  
#>      BIC: 234.81  
#>  
#> 
```

``` r
# (this model uses reticulate so it not very convenient as an example…)
model_reservoir$fixed_model
#> <reservoir_ensemble.JoblibReservoirEnsemble object at 0x78d97c756990>
```

Also a `call` attribute exists, meaning one can trained the model with
new inputs using `update` command:

``` r
new_model_reservoir <- update(model_reservoir, data = new_data, maxiter = new_maxiter)
```

# 6 Post-fit functions

The following functions are common to all fitted MixedML models.

## 6.1 `summary`

``` r
summary(model_reservoir)
#> 
#> 
#>  == MixedML model ==
#>   Type of the fixed effect model: reservoir 
#>   Number of iterations: 30 
#>   Best iteration: 24 
#>     MSE-train: 7.58 
#>     MSE-val: 1.05 
#>     loglik-train: -113 
#>     loglik-val: -29.1 
#> 
#> 
#>  === Reservoir Computing model (ReservoirPy) ===
#> ESN ensemble data:
#>   Number of reservoirs in the ensemble: 5 
#>   Aggregator: median 
#>   Data scaler: standard 
#> ESN data:
#>   Feedback connection: FALSE 
#>   Input-to-Readout: FALSE 
#> Reservoirs data:
#>   Number of reservoir units: 20 
#>   Leak rate: 1 
#>   Spectral radius: 0.1 
#>   Input Scaling: 1 
#> Readout data:
#>   Ridge regression parameter: 1e-05 
#> 
#> 
#>  == Random HLME model ==
#> Heterogenous linear mixed model 
#>      fitted by maximum likelihood method 
#>  
#> hlme(fixed = ym ~ 1, random = ~1 + x1 + x2, subject = "ID", idiag = TRUE, 
#>     cor = NULL, data = data, convB = 1e-04, convL = 1e-04, convG = 1e-04, 
#>     maxiter = 50, na.action = 1, posfix = 1, verbose = FALSE, 
#>     var.time = "time", nproc = 1)
#>  
#> Statistical Model: 
#>      Dataset: data 
#>      Number of subjects: 8 
#>      Number of observations: 34 
#>      Number of observations deleted: 4 
#>      Number of latent classes: 1 
#>      Number of parameters: 5  
#>      Number of estimated parameters: 4  
#>  
#> Iteration process: 
#>      Convergence criteria satisfied 
#>      Number of iterations:  1 
#>      Convergence criteria: parameters= 1.3e-09 
#>                          : likelihood= 7.4e-09 
#>                          : second derivatives= 1.7e-10 
#>  
#> Goodness-of-fit statistics: 
#>      maximum log-likelihood: -113.25  
#>      AIC: 234.5  
#>      BIC: 234.81  
#>  
#>  
#> Maximum Likelihood Estimates: 
#>  
#> Fixed effects in the longitudinal model:
#> 
#>               coef  Se Wald p-value
#> intercept  0.00000*                
#> 
#> 
#> Variance-covariance matrix of the random-effects:
#>           intercept   x1 x2
#> intercept      52.2        
#> x1              0.0 13.8   
#> x2              0.0  0.0  0
#> 
#>                              coef      Se
#> Residual standard error:  3.17282 0.48942
#> 
#>  * coefficient fixed by the user 
#> 
#> NULL
```

## 6.2 `plot_convergence`

``` r
plot_convergence(model = model_reservoir, ylog_mse = TRUE)
```

<img src="man/figures/README-unnamed-chunk-14-1.png" width="100%" />

## 6.3 `plot_prediction_check`

``` r
plot_predictions_check(model = model_reservoir)
```

<img src="man/figures/README-unnamed-chunk-15-1.png" width="100%" />

## 6.4 `predict`

``` r
pred_test_past <- predict(
  model = model_reservoir,
  data = data_test,
  all_info_hlme_prediction = FALSE,
  nproc_hlme_past = 1
)
pred_test_past
#>   47    8   20    3   41 
#>   NA 72.2 75.8 79.5 78.3
```

``` r
pred_test_all <- predict(
  model = model_reservoir,
  data = data_test,
  all_info_hlme_prediction = TRUE,
  nproc_hlme_past = 1
)
pred_test_all
#>   47    8   20    3   41 
#> 82.6 77.4 77.3 80.4 78.7
```

## 6.5 `plot_predictions`

``` r
hlme_model <- lcmm::hlme(
  fixed = ym ~ 1 + x1 + x2 + x3,
  random = ~ 1 + x1 + x2,
  data = data_train,
  subject = "ID",
  var.time = "time"
)
hlme_preds <- lcmm::predictY(hlme_model, newdata = data_test)
hlme_preds_all <- hlme_preds$pred
names(hlme_preds_all) <- rownames(hlme_preds$times)

plot_predictions(
  model = model_reservoir,
  data_pred = data_test,
  list_preds = list(
    mixedml_all_info = pred_test_all,
    mixedml_past_info = pred_test_past,
    hlme_all_info = hlme_preds_all
  ),
  ncols = 1
)
```

<img src="man/figures/README-unnamed-chunk-18-1.png" width="100%" />

## 6.6 `save_mixedml`

This function is used to save a mixedML model. It is **mandatory** when
using a model based on a Python package, since we need to save both R
and Python objects.

``` r
save_mixedml(model_reservoir, mixedml_model_rds = "model_reservoir.Rds")
```

## 6.7 `load_mixedml`

This function is used to load a mixedML model. It is **mandatory** when
using a model based on a Python package, since we need to load both R
and Python objects.

``` r
mixedml_model <- load_mixedml("model_reservoir.Rds")
```

``` r
mixedml_model$fixed_model
#> <reservoir_ensemble.JoblibReservoirEnsemble object at 0x78d97c757ed0>
```

``` r
mixedml_model$random_model
#> Heterogenous linear mixed model 
#>      fitted by maximum likelihood method 
#>  
#> hlme(fixed = ym ~ 1, random = ~1 + x1 + x2, subject = "ID", idiag = TRUE, 
#>     cor = NULL, data = data, convB = 1e-04, convL = 1e-04, convG = 1e-04, 
#>     maxiter = 50, na.action = 1, posfix = 1, verbose = FALSE, 
#>     var.time = "time", nproc = 1)
#>  
#> Statistical Model: 
#>      Dataset: data 
#>      Number of subjects: 8 
#>      Number of observations: 34 
#>      Number of observations deleted: 4 
#>      Number of latent classes: 1 
#>      Number of parameters: 5  
#>      Number of estimated parameters: 4  
#>  
#> Iteration process: 
#>      Convergence criteria satisfied 
#>      Number of iterations:  1 
#>      Convergence criteria: parameters= 1.3e-09 
#>                          : likelihood= 7.4e-09 
#>                          : second derivatives= 1.7e-10 
#>  
#> Goodness-of-fit statistics: 
#>      maximum log-likelihood: -113.25  
#>      AIC: 234.5  
#>      BIC: 234.81  
#>  
#> 
```

# 7 Remark on logging

The use of reticulate makes it cumbersome to implement logging in the
package. Since the solutions found involve preventing the use of Rstudio
and favor running from terminal, one simple solution is to write a
standard R script and call it from the terminal, redirecting both stdout
and stderr to a log file:

``` bash
Rscript name_of_script.R > log_file.log 2>&1
```

# 8 Working with Python

The `reticulate` package is used to extend the choice of ML models to
the ones available in Python packages.

One can either:

- let `reticulate` create a specific environment,
- use `reticulate` with a user controlled environment.

**Notes to developers:**

To declare the necessary libraries to `reticulate`, the `py_require`
command is used. Its documentation can be found
[here](https://pkgs.rstudio.com/reticulate/reference/py_require.html).

`mixedML` reads the `requirements.txt` file (standard for Python
installation) to generate the corresponding `py_require` commands. So in
order to add new dependencies, the `requirements.txt` file is the only
file to change.

This file can be found in the `inst/python` folder, along a
`requirements-dev.txt` that defines the requirements… for the
developers.

## 8.1 Let `reticulate` handles the installation

Nothing special is needed…

In this case `reticulate` will create an “ephemeral environments”, that
will be stored in a cache folder on your computer (as an example, on my
Linux computer, the folder is `.cache/R/reticulate/uv/cache/`).

## 8.2 Use `reticulate` with a user controlled environement

In this case one needs to:

1.  install the require libraries,
2.  set up an environment variable to tell `reticulate` where to find
    the libraries.

### 8.2.1 Installation

A `venv` or `conda` environment can be used. One must install the
necessary Python packages defined in :

- the `inst/python/requirements.txt` lists the packages needed to run
  all the ML models.
- the `inst/python/requirements-dev.txt` lists the packages needed for
  developers.

### 8.2.2 Setup of the `RETICULATE_PYTHON_ENV` environment variable

Before using `reticulate` it is necessary to set up either the
`RETICULATE_PYTHON` or the `RETICULATE_PYTHON_ENV` environment variable,
as explained in the `reticulate`
[documentation](https://rstudio.github.io/reticulate/articles/versions.html).

To define such environment variable, one can use a R command. For
example:

``` r
Sys.setenv(RETICULATE_PYTHON_ENV = "name of the environement")
```

A **convenient solution** is to write such command in the `.Rprofile`
file of a project, to be executed automatically when this project is
loaded. This allows different projects to use different variables.

**Please note** that if `reticulate` has already been called, then one
must restart the R session after changing these variables.

## 8.3 Note to devs

Specific helpers are available in the `R/utils.R` files.

It is important to make sure that the R object are properly transfered
to Python, with the expected classes. See [Type
Conversions](https://cran.r-project.org/web/packages/reticulate/vignettes/calling_python.html)
in `reticulate` documentation. One tricky example: a user will enter `1`
as an integer, but this is actually a `numeric` in R, which will become
a `float` in Python. So if an `int` is expected on Python side, one
needs to use `as.integer`.
