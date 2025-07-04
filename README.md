
  - [1 Introduction](#1-introduction)
  - [2 Method](#2-method)
  - [3 Example dataset](#3-example-dataset)
  - [4 General principle](#4-general-principle)
  - [5 Arguments](#5-arguments)
      - [5.1 Attributes](#51-attributes)
  - [6 Functions](#6-functions)
      - [6.1 `predict`](#61-predict)
      - [6.2 `plot_conv`](#62-plot_conv)
      - [6.3 `plot_last_iter`](#63-plot_last_iter)

<!-- README.md is generated from README.Rmd. Please edit that file -->

# 1 Introduction

This package provides functions to train hybrid mixed effects models.
Such models are a variation of linear mixed effects models, used for
Gaussian longitudinal data, whose formulation is:

  
![Y\_{ij} = X\_{ij} \\beta + Z\_{ij} u\_i + w\_{ij} +
\\varepsilon\_{ij}](https://latex.codecogs.com/png.image?%5Cdpi%7B110%7D&space;%5Cbg_white&space;Y_%7Bij%7D%20%3D%20X_%7Bij%7D%20%5Cbeta%20%2B%20%20Z_%7Bij%7D%20u_i%20%2B%20w_%7Bij%7D%20%2B%20%5Cvarepsilon_%7Bij%7D
"Y_{ij} = X_{ij} \\beta +  Z_{ij} u_i + w_{ij} + \\varepsilon_{ij}")  

… where
![i](https://latex.codecogs.com/png.image?%5Cdpi%7B110%7D&space;%5Cbg_white&space;i
"i") is the subject,
![j](https://latex.codecogs.com/png.image?%5Cdpi%7B110%7D&space;%5Cbg_white&space;j
"j") is the occasion, and
![w\_i](https://latex.codecogs.com/png.image?%5Cdpi%7B110%7D&space;%5Cbg_white&space;w_i
"w_i") comes from a zero-mean Gaussian stochastic process (such as
Brownian motion).

<br><br> For such hybrid models:

  - a Machine Leaning (ML) model is used to estimates the fixed effects;
  - a Mixed Effects model (`hlme` from [lcmm
    package](https://cecileproust-lima.github.io/lcmm/articles/lcmm.html))
    is constrained to estimate only random effects.

That is, the formulation becomes:

  
![Y\_{ij} = f\_{ML}(X\_{ij}) + Z\_{ij} u\_i + w\_{ij} +
\\varepsilon\_{ij}](https://latex.codecogs.com/png.image?%5Cdpi%7B110%7D&space;%5Cbg_white&space;Y_%7Bij%7D%20%3D%20f_%7BML%7D%28X_%7Bij%7D%29%20%2B%20%20Z_%7Bij%7D%20u_i%20%2B%20w_%7Bij%7D%20%2B%20%5Cvarepsilon_%7Bij%7D
"Y_{ij} = f_{ML}(X_{ij}) +  Z_{ij} u_i + w_{ij} + \\varepsilon_{ij}")  

… where
![f\_{ML}(X\_{ij})](https://latex.codecogs.com/png.image?%5Cdpi%7B110%7D&space;%5Cbg_white&space;f_%7BML%7D%28X_%7Bij%7D%29
"f_{ML}(X_{ij})") is the output from a ML model trained to predict the
fixed effects.

<br><br> Using ML models to estimates the fixed effects has two main
advantages comparing to linear models:

  - they can handle highly non-linear relations, and do so with simple
    inputs (instead of being highly dependent of the specification);
  - they can handle complex time interactions, in the case of Recurrent
    Neural Networks;

However, some ML models have a “black box” effect, as one cannot use its
estimated parameters to understand the relations within the data.

# 2 Method

The method uses a iterative training of both fixed effects and random
effects models. The pseudo-code is as follow (`fe`/`re` stands for
fixed/random effects):

    ml_model_fe <- initiate_ml_model_fe()
    hlme_model_re <- initiate_hlme_model_re()
    
    Yre <- 0.
    while not converged:
      fit ml_model_fe on X and (Y - Yre)
      Yfe <-  ml_model_fe(X)
    
      fit hlme_model_re on X and (Y - Yfe)
      Yre <-  hlme_model_re(X)
    
      converged <- criterion(Y, Yfe+Yre)

# 3 Example dataset

The dataset `data_mixedml` is proposed. It is generated using the
`R/data_gen.R` file.

It is a synthetic longitudinal dataset, containing data for 10 subjects
on 5 regularly spaced time steps. It contains two response columns for
both fixed and mixed effects. NA values have been added manually in
these columns:

``` r
data_mixedml
#>    ID time    x1    x2 x3    yf    ym
#> 1   1    0 10.38 100.6  1 205.9 191.5
#> 2   1    1    NA 103.5  1    NA    NA
#> 3   1    2  9.82  97.9  1 196.3 182.3
#> 4   1    3 11.01  98.2  1 214.3 199.8
#> 5   1    4  8.89  98.5  1 182.6 169.0
#> 6   2    0 10.38  97.5  0 100.7  89.4
#> 7   2    1  9.35  99.3  0    NA    NA
#> 8   2    2  9.60    NA  0  96.8  86.3
#> 9   2    3  9.10 102.2  0  96.6  86.4
#> 10  2    4  9.98 103.8  0 101.8  90.8
#> 11  3    0 11.08  97.0  1 214.6 237.6
#> 12  3    1  9.11  97.3  1 185.4 206.4
#> 13  3    2 10.43  96.0  1 204.5 226.7
#> 14  3    3  9.14 105.8  1 190.0 212.1
#> 15  3    4 10.07 102.0  1 202.0 224.6
#> 16  4    0  9.96  98.8  0  99.2  89.9
#> 17  4    1 10.43 100.6  0 102.4  93.0
#> 18  4    2 10.17 101.2  0 101.5  91.9
#> 19  4    3  9.71 104.9  0 101.0  90.7
#> 20  4    4 10.39  99.8  0 101.9  92.6
#> 21  5    0  9.65  99.1  1 194.3 186.4
#> 22  5    1  9.41  99.6  1 190.9 183.1
#> 23  5    2 10.63 102.1  1 210.6 202.1
#> 24  5    3  9.84 100.6  1 197.9 189.9
#> 25  5    4 10.02  96.3  1 198.4 190.4
#> 26  6    0  9.26  99.8  0  96.2 109.5
#> 27  6    1  9.44  97.6  0  96.0 109.1
#> 28  6    2  9.12  91.2  0  91.2 103.5
#> 29  6    3  9.47  98.1  0  96.4 109.6
#> 30  6    4  9.33  98.3  0  95.8 109.0
#> 31  7    0 10.38 104.5  1 207.9 186.2
#> 32  7    1  9.68 102.7  1 196.5 175.4
#> 33  7    2 10.72  99.0  1 210.2 189.3
#> 34  7    3  9.69  96.1  1 193.4 173.4
#> 35  7    4 10.11 100.0  1 201.7 180.9
#> 36  8    0 10.13 103.0  0 102.2 101.0
#> 37  8    1 10.21 101.2  0 101.7 100.6
#> 38  8    2  9.26 104.3  0  98.4  96.9
#> 39  8    3 10.09 100.4  0 100.7  99.6
#> 40  8    4 11.03  96.0  0 103.1 102.6
#> 41  9    0 10.36  98.5  1 204.7 197.1
#> 42  9    1  9.76  97.3  1 195.0 187.7
#> 43  9    2  9.76 101.0  1 196.8 189.5
#> 44  9    3 10.92 100.9  1 214.3 206.4
#> 45  9    4 10.26  96.9  1 202.3 194.8
#> 46 10    0  9.44 101.2  0  97.8  73.7
#> 47 10    1  9.84 102.4  0 100.4  76.0
#> 48 10    2 10.05  98.3  0  99.4  75.7
#> 49 10    3 10.32 100.5  0 101.9  77.6
#> 50 10    4 10.19 100.1  0 101.0  76.9
```

# 4 General principle

The MixedML models are obtained using specific functions which have for
signature:

``` r
some_mixed_ml_model(
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
  # controls (extra-parameters) for the implemented ML model
  controls_1, controls_2, et_caetera
)
```

# 5 Arguments

The `fixed_spec`, `random_spec`, `cor`, `data`, `subject` and `time` are
used by both sub-models and are taken from the `hlme` function which can
be seen in [the lcmm package
documentation](https://cecileproust-lima.github.io/lcmm/reference/hlme.html)

Then several controls are defined, using specific functions whose names
correspond to the control names. That is, the `some_name_ctrls(…)`
function is used to define `some_name_controls` controls. Each control
has its specific help.

Here is an example using the `reservoir_mixedml` function (here is the
[corresponding vignette](mixedML_reservoir.html):

``` r
model_reservoir <- reservoir_mixedml(
  fixed_spec = ym ~ x1 + x2 + x3,
  random_spec = ~ x1 + x2,
  data = data_mixedml,
  subject = "ID",
  time = "time",
  # parameters for MixedML method
  mixedml_controls = mixedml_ctrls(),
  # controls (extra-parameters) for the hlme model
  hlme_controls = hlme_ctrls(maxiter = 50, idiag = TRUE),
  # controls (extra-parameters) for the ML model
  esn_controls = esn_ctrls(units = 20, ridge = 1e-5),
  ensemble_controls = ensemble_ctrls(seed_list = c(1, 2, 3, 4, 5)),
  fit_controls = fit_ctrls(warmup = 2)
)
#> conda environment "01" activated!
#> step#0
#>  fitting fixed effects...
#>  fitting random effects...
#> Warning in reservoir_mixedml(fixed_spec = ym ~ x1 + x2 + x3, random_spec = ~x1
#> + : 3 observations could not be uses to train (either no fixed preds, random
#> preds or target).
#>  MSE = 482.6
#> step#1
#>  fitting fixed effects...
#>  fitting random effects...
#>  MSE = 162.7
#> step#2
#>  fitting fixed effects...
#>  fitting random effects...
#>  MSE = 67.37
#> step#3
#>  fitting fixed effects...
#>  fitting random effects...
#>  MSE = 28.61
#> step#4
#>  fitting fixed effects...
#>  fitting random effects...
#>  MSE = 4.964
#> step#5
#>  fitting fixed effects...
#>  fitting random effects...
#>  MSE = 5.608
#> step#6
#>  fitting fixed effects...
#>  fitting random effects...
#>  MSE = 4.283
#> step#7
#>  fitting fixed effects...
#>  fitting random effects...
#>  MSE = 4.149
#> step#8
#>  fitting fixed effects...
#>  fitting random effects...
#>  MSE = 4.37
#> step#9
#>  fitting fixed effects...
#>  fitting random effects...
#>  MSE = 4.713
#> step#10
#>  fitting fixed effects...
#>  fitting random effects...
#>  MSE = 5.086
```

The resulting model will be used in the remaining sections.

## 5.1 Attributes

Each sub-models are accessible from the fitted MixedML model:

``` r
model_reservoir$random_model
#> Heterogenous linear mixed model 
#>      fitted by maximum likelihood method 
#>  
#> hlme(fixed = ym ~ 1, random = ~x1 + x2, subject = "ID", idiag = TRUE, 
#>     cor = NULL, data = data, convB = 1e-04, convL = 1e-04, convG = 1e-04, 
#>     maxiter = 50, na.action = 1, posfix = 1, verbose = FALSE, 
#>     var.time = "time", nproc = 1)
#>  
#> Statistical Model: 
#>      Dataset: data 
#>      Number of subjects: 10 
#>      Number of observations: 47 
#>      Number of observations deleted: 3 
#>      Number of latent classes: 1 
#>      Number of parameters: 5  
#>      Number of estimated parameters: 4  
#>  
#> Iteration process: 
#>      Convergence criteria satisfied 
#>      Number of iterations:  8 
#>      Convergence criteria: parameters= 1.8e-07 
#>                          : likelihood= 1.3e-08 
#>                          : second derivatives= 6.8e-10 
#>  
#> Goodness-of-fit statistics: 
#>      maximum log-likelihood: -139.56  
#>      AIC: 287.12  
#>      BIC: 288.33  
#>  
#> 
```

``` r
# (this model uses reticulate so it not very convenient as an example…)
model_reservoir$fixed_model
#> <reservoir_ensemble.JoblibReservoirEnsemble object at 0x77aa7fd6d6a0>
```

Also a `call` attribute exists, meaning one can trained the model with
new inputs using `update` command:

``` r
new_model_reservoir <- update(model_reservoir, data = new_data, maxiter = new_maxiter)
```

# 6 Functions

The function `predict`, `plot_conv` and `plot_last_iter` are common to
all fitted MixedML models.

## 6.1 `predict`

**Description**

Predict using a fitted model and new data

**Usage**

``` r
predict(model, data)
```

**Arguments**

  - `model`: Trained MixedML model
  - `data`: New data (same format as the one used for training)

**Value**

prediction

## 6.2 `plot_conv`

**Description**

Plot the (MSE) convergence of the MixedML training

**Usage**

``` r
plot_conv(model, ylog = TRUE)
```

**Arguments**

  - `model`: Trained MixedML model
  - `ylog`: Plot the y-value with a log scale. Default: TRUE.

**Value**

Convergence plot

``` r
plot_conv(model = model_reservoir)
```

<img src="man/figures/README-unnamed-chunk-14-1.png" width="100%" />

## 6.3 `plot_last_iter`

**Description**

Plot the prediction of a MixedML model

**Usage**

``` r
plot_last_iter(model, subject_nb_or_list, ylog = FALSE)
```

**Arguments**

  - `model`: Trained MixedML model.
  - `subject_nb_or_list`: Number of subjects to plot (randomly selected)
    or list of subjects to plot.
  - `ylog`: Plot the y-value with a log scale. Default: TRUE.

**Value**

Prediction plot of the model.

    #> Subjects selected randomly: use set.seed to change the selection.

<img src="man/figures/README-unnamed-chunk-16-1.png" width="100%" />
