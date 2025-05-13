Presentation of the mixedML package
================

# Introduction

This package provides functions to train hybrid mixed effects models.
These models combine: - a Machine Leaning (ML) model to estimates the
fixed effects; - a Mixed Effects model (from
[lcmm](https://github.com/CecileProust-Lima/lcmm/)) to estimate the
random effects.

Using ML models allows to use highly non-linear modelization of the
fixed effects, as well as complex time interactions when using Recurrent
Neural Networks.

The method used is model agnostic, so any kind of ML model can be
implement.

So far, a hybrid model based on Reservoir Computing is available. They
are implemented by interfacing the
[reservoirpy](https://github.com/reservoirpy/reservoirpy) Python package
with R using [reticulate](https://github.com/rstudio/reticulate).

# MixedML use

## General principle

The MixedML models are obtained using specific functions which have for
signature:

``` r
some_mixed_ml_model(
  # parameters of the MixedML model (inpired by the hlme function definition)
  fixed_spec,
  random_spec,
  data,
  subject,
  time,
  # parameters for MixedML method
  mixedml_controls,
  # controls (extra-parameters) for the hlme model
  hlme_controls,
  # controls (extra-parameters) for the ML model
  controls_1, controls_2, et_caetera
)
```

The `fixed_spec`, `random_spec`, `cor`, `data`, `subject` and `time`
parameters are taken from the `hlme` function and can be seen in [the
lcmm package
documentation](https://cecileproust-lima.github.io/lcmm/reference/hlme.html)

## Controls

Controls are defined using specific functions, whose names correspond to
the control names: the `some_name_ctrls` function is used to define
`some_name_controls` controls.

`mixedml_controls` and `hlme_controls` are common to all MixedML models.

### `mixedml_controls`

<!DOCTYPE html><html><head><title>R: Prepare the mixedml_controls</title>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=yes" />
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.15.3/dist/katex.min.css">
<script type="text/javascript">
const macros = { "\\R": "\\textsf{R}", "\\code": "\\texttt"};
function processMathHTML() {
    var l = document.getElementsByClassName('reqn');
    for (let e of l) { katex.render(e.textContent, e, { throwOnError: false, macros }); }
    return;
}</script>
<script defer src="https://cdn.jsdelivr.net/npm/katex@0.15.3/dist/katex.min.js"
    onload="processMathHTML();"></script>
<link rel="stylesheet" type="text/css" href="R.css" />
</head><body><div class="container"><main>
&#10;<table style="width: 100%;"><tr><td>mixedml_ctrls</td><td style="text-align: right;">R Documentation</td></tr></table>
&#10;<h2>Prepare the mixedml_controls</h2>
&#10;<h3>Description</h3>
&#10;<p>Prepare the mixedml_controls
</p>
&#10;
<h3>Usage</h3>
&#10;<pre><code class='language-R'>mixedml_ctrls(patience = 2, conv_ratio_thresh = 0.01)
</code></pre>
&#10;
<h3>Arguments</h3>
&#10;<table role = "presentation">
<tr><td><code id="patience">patience</code></td>
<td>
<p>Number of iterations without improvement before the training is stopped. Default: 2</p>
</td></tr>
<tr><td><code id="conv_ratio_thresh">conv_ratio_thresh</code></td>
<td>
<p>Ratio of improvement of the MSE to consider an improvement.
<code>conv_ratio_thresh=0.01</code> means an improvement of at least 1% of the MSE is necessary. Default: 0.01</p>
</td></tr>
</table>
&#10;
<h3>Value</h3>
&#10;<p>mixedml_controls
</p>
&#10;</main>
&#10;</div>
</body></html>

### `hlme_controls`

<!DOCTYPE html><html><head><title>R: Prepare the hlme_controls</title>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=yes" />
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.15.3/dist/katex.min.css">
<script type="text/javascript">
const macros = { "\\R": "\\textsf{R}", "\\code": "\\texttt"};
function processMathHTML() {
    var l = document.getElementsByClassName('reqn');
    for (let e of l) { katex.render(e.textContent, e, { throwOnError: false, macros }); }
    return;
}</script>
<script defer src="https://cdn.jsdelivr.net/npm/katex@0.15.3/dist/katex.min.js"
    onload="processMathHTML();"></script>
<link rel="stylesheet" type="text/css" href="R.css" />
</head><body><div class="container"><main>
&#10;<table style="width: 100%;"><tr><td>hlme_ctrls</td><td style="text-align: right;">R Documentation</td></tr></table>
&#10;<h2>Prepare the hlme_controls</h2>
&#10;<h3>Description</h3>
&#10;<p>Please see the <a href="https://cecileproust-lima.github.io/lcmm/reference/hlme.html">documentation</a>
of the <code>hlme</code> function of the <code>lcmm</code> package.
</p>
&#10;
<h3>Usage</h3>
&#10;<pre><code class='language-R'>hlme_ctrls(cor = NULL, idiag = FALSE, maxiter = 500, nproc = 1)
</code></pre>
&#10;
<h3>Arguments</h3>
&#10;<table role = "presentation">
<tr><td><code id="cor">cor</code></td>
<td>
<p>brownian motion or autoregressive process modeling the correlation
between the observations. &quot;BM&quot; or &quot;AR&quot; should be specified, followed by the time variable between brackets.</p>
</td></tr>
<tr><td><code id="idiag">idiag</code></td>
<td>
<p>logical for the structure of the variance-covariance matrix of the random-effects.
If FALSE, a non structured matrix of variance-covariance is considered (by default).
If TRUE a diagonal matrix of variance-covariance is considered.</p>
</td></tr>
<tr><td><code id="maxiter">maxiter</code></td>
<td>
<p>maximum number of iterations for the Marquardt iterative algorithm.</p>
</td></tr>
<tr><td><code id="nproc">nproc</code></td>
<td>
<p>the number cores for parallel computation. Default to 1 (sequential mode).</p>
</td></tr>
</table>
&#10;
<h3>Value</h3>
&#10;<p>hlme_controls
</p>
&#10;</main>
&#10;</div>
</body></html>

## Functions

The function `predict` and `plot_conv` are common to all the MixedML
models

### `predict`

<!DOCTYPE html><html><head><title>R: Predict using a fitted model and new data</title>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=yes" />
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.15.3/dist/katex.min.css">
<script type="text/javascript">
const macros = { "\\R": "\\textsf{R}", "\\code": "\\texttt"};
function processMathHTML() {
    var l = document.getElementsByClassName('reqn');
    for (let e of l) { katex.render(e.textContent, e, { throwOnError: false, macros }); }
    return;
}</script>
<script defer src="https://cdn.jsdelivr.net/npm/katex@0.15.3/dist/katex.min.js"
    onload="processMathHTML();"></script>
<link rel="stylesheet" type="text/css" href="R.css" />
</head><body><div class="container"><main>
&#10;<table style="width: 100%;"><tr><td>predict</td><td style="text-align: right;">R Documentation</td></tr></table>
&#10;<h2>Predict using a fitted model and new data</h2>
&#10;<h3>Description</h3>
&#10;<p>Predict using a fitted model and new data
</p>
&#10;
<h3>Usage</h3>
&#10;<pre><code class='language-R'>predict(model, data)
</code></pre>
&#10;
<h3>Arguments</h3>
&#10;<table role = "presentation">
<tr><td><code id="model">model</code></td>
<td>
<p>Trained MixedML model</p>
</td></tr>
<tr><td><code id="data">data</code></td>
<td>
<p>New data (same format as the one used for training)</p>
</td></tr>
</table>
&#10;
<h3>Value</h3>
&#10;<p>prediction
</p>
&#10;</main>
&#10;</div>
</body></html>

### `plot_conv`

<!DOCTYPE html><html><head><title>R: Plot the (MSE) convergence of the MixedML training</title>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=yes" />
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.15.3/dist/katex.min.css">
<script type="text/javascript">
const macros = { "\\R": "\\textsf{R}", "\\code": "\\texttt"};
function processMathHTML() {
    var l = document.getElementsByClassName('reqn');
    for (let e of l) { katex.render(e.textContent, e, { throwOnError: false, macros }); }
    return;
}</script>
<script defer src="https://cdn.jsdelivr.net/npm/katex@0.15.3/dist/katex.min.js"
    onload="processMathHTML();"></script>
<link rel="stylesheet" type="text/css" href="R.css" />
</head><body><div class="container"><main>
&#10;<table style="width: 100%;"><tr><td>plot_conv</td><td style="text-align: right;">R Documentation</td></tr></table>
&#10;<h2>Plot the (MSE) convergence of the MixedML training</h2>
&#10;<h3>Description</h3>
&#10;<p>Plot the (MSE) convergence of the MixedML training
</p>
&#10;
<h3>Usage</h3>
&#10;<pre><code class='language-R'>plot_conv(model, ylog = TRUE)
</code></pre>
&#10;
<h3>Arguments</h3>
&#10;<table role = "presentation">
<tr><td><code id="model">model</code></td>
<td>
<p>Trained MixedML model</p>
</td></tr>
<tr><td><code id="ylog">ylog</code></td>
<td>
<p>Plot the y-value with a log scale. Default: TRUE.</p>
</td></tr>
</table>
&#10;
<h3>Value</h3>
&#10;<p>Convergence plot
</p>
&#10;</main>
&#10;</div>
</body></html>

# MixedML with Reservoir Computing

The function `reservoir_mixedml` is used to define and fit a MixedML
model which uses an Reservoir Computing to fit the fixed effect.

<!DOCTYPE html><html><head><title>R: MixedML model with Reservoir Computing</title>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=yes" />
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.15.3/dist/katex.min.css">
<script type="text/javascript">
const macros = { "\\R": "\\textsf{R}", "\\code": "\\texttt"};
function processMathHTML() {
    var l = document.getElementsByClassName('reqn');
    for (let e of l) { katex.render(e.textContent, e, { throwOnError: false, macros }); }
    return;
}</script>
<script defer src="https://cdn.jsdelivr.net/npm/katex@0.15.3/dist/katex.min.js"
    onload="processMathHTML();"></script>
<link rel="stylesheet" type="text/css" href="R.css" />
</head><body><div class="container"><main>
&#10;<table style="width: 100%;"><tr><td>reservoir_mixedml</td><td style="text-align: right;">R Documentation</td></tr></table>
&#10;<h2>MixedML model with Reservoir Computing</h2>
&#10;<h3>Description</h3>
&#10;<p>Generate and fit a MixedML model using an Ensemble of Echo State Networks (Reservoir+Ridge Regression)
to fit the fixed effects.
</p>
&#10;
<h3>Usage</h3>
&#10;<pre><code class='language-R'>reservoir_mixedml(
  fixed_spec,
  random_spec,
  data,
  subject,
  time,
  mixedml_controls = mixedml_ctrls(),
  hlme_controls = hlme_ctrls(),
  esn_controls = esn_controls(),
  ensemble_controls = ensemble_controls(),
  fit_controls = fit_controls(),
  predict_controls = predict_controls()
)
</code></pre>
&#10;
<h3>Arguments</h3>
&#10;<table role = "presentation">
<tr><td><code id="fixed_spec">fixed_spec</code></td>
<td>
<p>two-sided linear formula object for the fixed-effects.
The response outcome is on the left of ~ and the covariates are separated by + on the right of ~.</p>
</td></tr>
<tr><td><code id="random_spec">random_spec</code></td>
<td>
<p>two-sided formula for the random-effects in the linear mixed model.
The response outcome is on the left of ~ and the covariates are separated by + on the right of ~.
By default, an intercept is included. If no intercept, -1 should be the first term included.</p>
</td></tr>
<tr><td><code id="data">data</code></td>
<td>
<p>dataframe containing the variables named in <code>fixed_spec</code>, <code>random_spec</code>, <code>subject</code> and <code>time</code>.</p>
</td></tr>
<tr><td><code id="subject">subject</code></td>
<td>
<p>name of the covariate representing the grouping structure, given as a string/character.</p>
</td></tr>
<tr><td><code id="time">time</code></td>
<td>
<p>name of the time variable, given as a string/character.</p>
</td></tr>
<tr><td><code id="mixedml_controls">mixedml_controls</code></td>
<td>
<p>controls specific to the MixedML model</p>
</td></tr>
<tr><td><code id="hlme_controls">hlme_controls</code></td>
<td>
<p>controls specific to the HLME model</p>
</td></tr>
<tr><td><code id="esn_controls">esn_controls</code></td>
<td>
<p>controls specific to the ESN models</p>
</td></tr>
<tr><td><code id="ensemble_controls">ensemble_controls</code></td>
<td>
<p>controls specific to the Ensemble model</p>
</td></tr>
<tr><td><code id="fit_controls">fit_controls</code></td>
<td>
<p>controls specific to the ESN models fit</p>
</td></tr>
<tr><td><code id="predict_controls">predict_controls</code></td>
<td>
<p>controls specific to the ESN models prediction</p>
</td></tr>
</table>
&#10;
<h3>Value</h3>
&#10;<p>fitted MixedML model
</p>
&#10;</main>
&#10;</div>
</body></html>

Reservoir Computing is implemented using an ensemble of Echo State
Network (Reservoir + Ridge readout), whose Reservoirs are initialized
with different random seeds. The prediction of the ensemble model is
calculated as the mean or median of all the ENS prediction, which
reduces the impact of the Reservoir initialization on the results.

Four controls are used to define the RC model’s behavior.

## `esn_controls`

<!DOCTYPE html><html><head><title>R: Prepare the esn_controls</title>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=yes" />
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.15.3/dist/katex.min.css">
<script type="text/javascript">
const macros = { "\\R": "\\textsf{R}", "\\code": "\\texttt"};
function processMathHTML() {
    var l = document.getElementsByClassName('reqn');
    for (let e of l) { katex.render(e.textContent, e, { throwOnError: false, macros }); }
    return;
}</script>
<script defer src="https://cdn.jsdelivr.net/npm/katex@0.15.3/dist/katex.min.js"
    onload="processMathHTML();"></script>
<link rel="stylesheet" type="text/css" href="R.css" />
</head><body><div class="container"><main>
&#10;<table style="width: 100%;"><tr><td>esn_ctrls</td><td style="text-align: right;">R Documentation</td></tr></table>
&#10;<h2>Prepare the esn_controls</h2>
&#10;<h3>Description</h3>
&#10;<p>Please see the documentation of ReservoirPy for:
</p>
&#10;<ul>
<li> <p><a href="https://reservoirpy.readthedocs.io/en/latest/api/generated/reservoirpy.nodes.Reservoir.html">Reservoir</a>
</p>
</li>
<li> <p><a href="https://reservoirpy.readthedocs.io/en/latest/api/generated/reservoirpy.nodes.Ridge.html">Ridge Regression</a>
</p>
</li></ul>
&#10;
&#10;<h3>Usage</h3>
&#10;<pre><code class='language-R'>esn_ctrls(units = 100, lr = 1, sr = 0.1, ridge = 0, feedback = FALSE)
</code></pre>
&#10;
<h3>Arguments</h3>
&#10;<table role = "presentation">
<tr><td><code id="units">units</code></td>
<td>
<p>Number of reservoir units.</p>
</td></tr>
<tr><td><code id="lr">lr</code></td>
<td>
<p>Neurons leak rate. Must be in <code class="reqn">[0,1]</code>.</p>
</td></tr>
<tr><td><code id="sr">sr</code></td>
<td>
<p>Spectral radius of recurrent weight matrix.</p>
</td></tr>
<tr><td><code id="ridge">ridge</code></td>
<td>
<p>Regularization parameter <code class="reqn">\lambda</code>.</p>
</td></tr>
<tr><td><code id="feedback">feedback</code></td>
<td>
<p>Is readout connected to reservoir through feedback?</p>
</td></tr>
</table>
&#10;
<h3>Value</h3>
&#10;<p>esn_controls
</p>
&#10;</main>
&#10;</div>
</body></html>

## `ensemble_controls`

<!DOCTYPE html><html><head><title>R: Prepare the ensemble_controls</title>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=yes" />
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.15.3/dist/katex.min.css">
<script type="text/javascript">
const macros = { "\\R": "\\textsf{R}", "\\code": "\\texttt"};
function processMathHTML() {
    var l = document.getElementsByClassName('reqn');
    for (let e of l) { katex.render(e.textContent, e, { throwOnError: false, macros }); }
    return;
}</script>
<script defer src="https://cdn.jsdelivr.net/npm/katex@0.15.3/dist/katex.min.js"
    onload="processMathHTML();"></script>
<link rel="stylesheet" type="text/css" href="R.css" />
</head><body><div class="container"><main>
&#10;<table style="width: 100%;"><tr><td>ensemble_ctrls</td><td style="text-align: right;">R Documentation</td></tr></table>
&#10;<h2>Prepare the ensemble_controls</h2>
&#10;<h3>Description</h3>
&#10;<p>Prepare the ensemble_controls
</p>
&#10;
<h3>Usage</h3>
&#10;<pre><code class='language-R'>ensemble_ctrls(seed_list = c(1, 2, 3), agg_func = "median", n_procs = 1)
</code></pre>
&#10;
<h3>Arguments</h3>
&#10;<table role = "presentation">
<tr><td><code id="seed_list">seed_list</code></td>
<td>
<p>List of seeds used to generate the Reservoir. Default:  c(1, 2, 3)</p>
</td></tr>
<tr><td><code id="agg_func">agg_func</code></td>
<td>
<p>Function used to aggregate the predictions of each ESN.
&quot;mean&quot; or &quot;median&quot;. Default: &quot;median&quot;</p>
</td></tr>
<tr><td><code id="n_procs">n_procs</code></td>
<td>
<p>Number of processor to use. 1 means no multiprocessing. Default: 1.</p>
</td></tr>
</table>
&#10;
<h3>Value</h3>
&#10;<p>ensemble_controls
</p>
&#10;</main>
&#10;</div>
</body></html>

## `fit_controls`

<!DOCTYPE html><html><head><title>R: Prepare the fit_controls</title>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=yes" />
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.15.3/dist/katex.min.css">
<script type="text/javascript">
const macros = { "\\R": "\\textsf{R}", "\\code": "\\texttt"};
function processMathHTML() {
    var l = document.getElementsByClassName('reqn');
    for (let e of l) { katex.render(e.textContent, e, { throwOnError: false, macros }); }
    return;
}</script>
<script defer src="https://cdn.jsdelivr.net/npm/katex@0.15.3/dist/katex.min.js"
    onload="processMathHTML();"></script>
<link rel="stylesheet" type="text/css" href="R.css" />
</head><body><div class="container"><main>
&#10;<table style="width: 100%;"><tr><td>fit_ctrls</td><td style="text-align: right;">R Documentation</td></tr></table>
&#10;<h2>Prepare the fit_controls</h2>
&#10;<h3>Description</h3>
&#10;<p>Please see the
<a href="https://reservoirpy.readthedocs.io/en/latest/api/generated/reservoirpy.nodes.ESN.html#reservoirpy.nodes.ESN.fit">documentation</a>
of ReservoirPy
</p>
&#10;
<h3>Usage</h3>
&#10;<pre><code class='language-R'>fit_ctrls(warmup = 0, stateful = TRUE, reset = FALSE)
</code></pre>
&#10;
<h3>Arguments</h3>
&#10;<table role = "presentation">
<tr><td><code id="warmup">warmup</code></td>
<td>
<p>Number of timesteps to consider as warmup and discard at the beginning. Defalut: 0
of each timeseries before training.</p>
</td></tr>
<tr><td><code id="stateful">stateful</code></td>
<td>
<p>If True, Node state will be updated by this operation. Default: TRUE</p>
</td></tr>
<tr><td><code id="reset">reset</code></td>
<td>
<p>If True, Nodes states will be reset to zero before this operation. Default: FALSE</p>
</td></tr>
</table>
&#10;
<h3>Value</h3>
&#10;<p>fit_controls
</p>
&#10;</main>
&#10;</div>
</body></html>

## `predict_controls`

<!DOCTYPE html><html><head><title>R: Prepare the predict_controls</title>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=yes" />
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.15.3/dist/katex.min.css">
<script type="text/javascript">
const macros = { "\\R": "\\textsf{R}", "\\code": "\\texttt"};
function processMathHTML() {
    var l = document.getElementsByClassName('reqn');
    for (let e of l) { katex.render(e.textContent, e, { throwOnError: false, macros }); }
    return;
}</script>
<script defer src="https://cdn.jsdelivr.net/npm/katex@0.15.3/dist/katex.min.js"
    onload="processMathHTML();"></script>
<link rel="stylesheet" type="text/css" href="R.css" />
</head><body><div class="container"><main>
&#10;<table style="width: 100%;"><tr><td>predict_ctrls</td><td style="text-align: right;">R Documentation</td></tr></table>
&#10;<h2>Prepare the predict_controls</h2>
&#10;<h3>Description</h3>
&#10;<p>Please see the
<a href="https://reservoirpy.readthedocs.io/en/latest/api/generated/reservoirpy.nodes.ESN.html#reservoirpy.nodes.ESN.run">documentation</a>
of ReservoirPy
</p>
&#10;
<h3>Usage</h3>
&#10;<pre><code class='language-R'>predict_ctrls(stateful = TRUE, reset = FALSE)
</code></pre>
&#10;
<h3>Arguments</h3>
&#10;<table role = "presentation">
<tr><td><code id="stateful">stateful</code></td>
<td>
<p>If True, Node state will be updated by this operation.</p>
</td></tr>
<tr><td><code id="reset">reset</code></td>
<td>
<p>If True, Nodes states will be reset to zero before this operation.</p>
</td></tr>
</table>
&#10;
<h3>Value</h3>
&#10;<p>predict_controls
</p>
&#10;</main>
&#10;</div>
</body></html>

# Example

``` r
model <- reservoir_mixedml(
  fixed_spec = Y ~ X1 + X2 + X3,
  random_spec = Y ~ X1 + X2 + X3,
  data = lcmm::data_hlme,
  subject = "ID",
  time = "Time",
  mixedml_controls = mixedml_ctrls(),
  hlme_controls = hlme_ctrls(nproc = 2, maxiter = 5000, idiag = TRUE),
  esn_controls = esn_ctrls(units = 5, ridge = 1e-5),
  ensemble_controls = ensemble_ctrls(seed_list = c(1, 2, 3, 4, 5), n_procs = 5),
  fit_controls = fit_ctrls(),
  predict_controls = predict_ctrls()
)
#> conda environment "01" activated!
#> step#0
#>  fitting fixed effects...
#>  fitting random effects...
#>  MSE = 5.469
#> step#1
#>  fitting fixed effects...
#>  fitting random effects...
#>  MSE = 5.47
#> step#2
#>  fitting fixed effects...
#>  fitting random effects...
#>  MSE = 5.469
#> step#3
#>  fitting fixed effects...
#>  fitting random effects...
#>  MSE = 5.468
```

``` r
summary(model$random_model)
#> Heterogenous linear mixed model 
#>      fitted by maximum likelihood method 
#>  
#> hlme(fixed = Y ~ 1, random = ~X1 + X2 + X3, subject = "ID", idiag = TRUE, 
#>     cor = NULL, data = data, maxiter = 5000, posfix = 1, var.time = "Time", 
#>     nproc = 2)
#>  
#> Statistical Model: 
#>      Dataset: data 
#>      Number of subjects: 100 
#>      Number of observations: 326 
#>      Number of latent classes: 1 
#>      Number of parameters: 6  
#>      Number of estimated parameters: 5  
#>  
#> Iteration process: 
#>      Convergence criteria satisfied 
#>      Number of iterations:  2 
#>      Convergence criteria: parameters= 1.4e-05 
#>                          : likelihood= 9.3e-07 
#>                          : second derivatives= 1.7e-11 
#>  
#> Goodness-of-fit statistics: 
#>      maximum log-likelihood: -951.02  
#>      AIC: 1912.03  
#>      BIC: 1925.06  
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
#>           intercept       X1       X2 X3
#> intercept  38.61825                     
#> X1          0.00000 16.68124            
#> X2          0.00000  0.00000 11.76276   
#> X3          0.00000  0.00000  0.00000  0
#> 
#>                              coef      Se
#> Residual standard error:  2.78031 0.13075
#> 
#>  * coefficient fixed by the user 
#> 
```

``` r
plot_conv(model)
```

![](/home/francois/Documents/SISTM/mixedML/README_files/figure-gfm/unnamed-chunk-16-1.png)<!-- -->
