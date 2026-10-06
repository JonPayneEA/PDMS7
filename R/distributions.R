# ============================================================ #
# Tool:         distributions
# Description:  Configurable PDM framework: distributions
# Flode Module: standalone; target reach.hydro
# Author:       Codex (AI-generated); human maintainer attribution not supplied
# Created:      2026-10-04
# Modified:     2026-10-05 - CX: Align with Flode Tier 3 target conventions
# Tier:         3
# Inputs:       Typed S7 components; depths in mm; time in hours
# Outputs:      Validated S7 objects or hydrological values with documented units
# Dependencies: S7; data.table; yaml; logger (structured logging; no fastverse equivalent)
# ============================================================ #

# Eq. 7: storage(C) = integral_0^C [1-F(c)] dc.
#' Create FlodeCapacityDistribution
#'
#' Component of the configurable Moore (2007) rainfall-runoff framework.
#'
#'
#' @return An S7 component object.
#'
#' @details This is an abstract extension class. Construct a concrete subclass.
#'
#' @references Moore (2007), doi:10.5194/hess-11-483-2007.
#' @export
FlodeCapacityDistribution <- S7::new_class("FlodeCapacityDistribution",
                                           package = "pdmS7",
                                           abstract = TRUE)
#' Create FlodeParetoCapacity
#'
#' Component of the configurable Moore (2007) rainfall-runoff framework.
#'
#' @param cmin Minimum point storage capacity in mm; nonnegative and below cmax.
#' @param cmax Maximum point storage capacity in mm; strictly above cmin.
#' @param b Nonnegative Pareto shape exponent; zero represents a point mass at cmax.
#'
#' @return An S7 component object.
#'
#' @examples
#' FlodeParetoCapacity(0, 140, 0.4)
#'
#' @references Moore (2007), doi:10.5194/hess-11-483-2007.
#' @export
FlodeParetoCapacity <- S7::new_class(
  "FlodeParetoCapacity",
  parent = FlodeCapacityDistribution,
  package = "pdmS7",
  properties = list(cmin = S7::class_numeric,
                    cmax = S7::class_numeric,
                    b = S7::class_numeric),

  validator = function(self) {
    .bounded_params(
      self, list(
        cmin = .scalar(self@cmin, 0),
        cmax = .scalar(self@cmax, self@cmin, strict = TRUE),
        b = .scalar(self@b, 0)
      )
    )
  }
)
#' Create FlodeRectangularCapacity
#'
#' Component of the configurable Moore (2007) rainfall-runoff framework.
#'
#' @param cmin Minimum point storage capacity in mm; nonnegative and below cmax.
#' @param cmax Maximum point storage capacity in mm; strictly above cmin.
#'
#' @return An S7 component object.
#'
#' @examples
#' FlodeRectangularCapacity(0, 200)
#'
#' @references Moore (2007), doi:10.5194/hess-11-483-2007.
#' @export
FlodeRectangularCapacity <- S7::new_class(
  "FlodeRectangularCapacity",
  parent = FlodeCapacityDistribution,
  package = "pdmS7",
  properties = list(cmin = S7::class_numeric,
                    cmax = S7::class_numeric),

  validator = function(self) {
    .bounded_params(
      self, list(
        cmin = .scalar(self@cmin, 0),
        cmax = .scalar(self@cmax, self@cmin, strict = TRUE)
      )
    )
  }
)
#' Create FlodeTriangularCapacity
#'
#' Component of the configurable Moore (2007) rainfall-runoff framework.
#'
#' @param cmin Minimum point storage capacity in mm; nonnegative and below cmax.
#' @param cmax Maximum point storage capacity in mm; strictly above cmin.
#'
#' @return An S7 component object.
#'
#' @examples
#' FlodeTriangularCapacity(0, 200)
#'
#' @references Moore (2007), doi:10.5194/hess-11-483-2007.
#' @export
FlodeTriangularCapacity <- S7::new_class(
  "FlodeTriangularCapacity",
  parent = FlodeCapacityDistribution,
  package = "pdmS7",
  properties = list(cmin = S7::class_numeric,
                    cmax = S7::class_numeric),

  validator = function(self) {
    .bounded_params(
      self, list(
        cmin = .scalar(self@cmin, 0),
        cmax = .scalar(self@cmax, self@cmin, strict = TRUE)
      )
    )
  }
)
#' Create FlodeExponentialCapacity
#'
#' Component of the configurable Moore (2007) rainfall-runoff framework.
#'
#' @param mean Positive mean point capacity in mm.
#'
#' @return An S7 component object.
#'
#' @examples
#' FlodeExponentialCapacity(100)
#'
#' @references Moore (2007), doi:10.5194/hess-11-483-2007.
#' @export
FlodeExponentialCapacity <- S7::new_class(
  "FlodeExponentialCapacity",
  parent = FlodeCapacityDistribution,
  package = "pdmS7",
  properties = list(mean = S7::class_numeric),

  validator = function(self) if (!.scalar(self@mean, 0, strict = TRUE)) "mean must be positive"
)
#' Create FlodeLognormalCapacity
#'
#' Component of the configurable Moore (2007) rainfall-runoff framework.
#'
#' @param meanlog Finite mean of log point capacity (capacity measured in mm).
#' @param sdlog Positive standard deviation of log point capacity.
#'
#' @return An S7 component object.
#'
#' @examples
#' FlodeLognormalCapacity(log(100) - 0.5, 1)
#'
#' @references Moore (2007), doi:10.5194/hess-11-483-2007.
#' @export
FlodeLognormalCapacity <- S7::new_class(
  "FlodeLognormalCapacity",
  parent = FlodeCapacityDistribution,
  package = "pdmS7",
  properties = list(meanlog = S7::class_numeric,
                    sdlog = S7::class_numeric),

  validator = function(self) {
    .bounded_params(
      self, list(
        meanlog = .scalar(self@meanlog),
        sdlog = .scalar(self@sdlog, 0, strict = TRUE),
        finite_mean = .scalar(
          exp(self@meanlog + self@sdlog^2 / 2),
          0,
          strict = TRUE
        )
      )
    )
  }
)

#' Capacity cdf
#'
#' Call capacity_cdf(x, c) for nonnegative point capacities c in mm.
#'
#' @param x An S7 capacity, routing, or recharge component, as required by the generic.
#' @param ... Method arguments: see Details for the component-specific calling convention.
#'
#' @return Numeric values or a component result as described in Details.
#'
#' @examples
#' capacity_cdf(FlodeParetoCapacity(0, 140, 0.4), c = c(0, 70, 140))
#'
#' @references Moore (2007), doi:10.5194/hess-11-483-2007.
#' @export
capacity_cdf <- S7::new_generic("capacity_cdf", "x")
#' Capacity pdf
#'
#' Call capacity_pdf(x, c). The Pareto b=0 point mass has no ordinary density.
#'
#' @param x An S7 capacity, routing, or recharge component, as required by the generic.
#' @param ... Method arguments: see Details for the component-specific calling convention.
#'
#' @return Numeric values or a component result as described in Details.
#'
#' @examples
#' capacity_pdf(FlodeExponentialCapacity(100), c = c(0, 100))
#'
#' @references Moore (2007), doi:10.5194/hess-11-483-2007.
#' @export
capacity_pdf <- S7::new_generic("capacity_pdf", "x")
#' Capacity mean
#'
#' Returns mean point capacity, also maximum basin soil storage Smax, in mm.
#'
#' @param x An S7 capacity, routing, or recharge component, as required by the generic.
#' @param ... Method arguments: see Details for the component-specific calling convention.
#'
#' @return Numeric values or a component result as described in Details.
#'
#' @examples
#' capacity_mean(FlodeParetoCapacity(0, 140, 0.4))
#'
#' @references Moore (2007), doi:10.5194/hess-11-483-2007.
#' @export
capacity_mean <- S7::new_generic("capacity_mean", "x")
#' Storage from capacity
#'
#' Call storage_from_capacity(x, c); integrates the capacity survival function.
#'
#' @param x An S7 capacity, routing, or recharge component, as required by the generic.
#' @param ... Method arguments: see Details for the component-specific calling convention.
#'
#' @return Numeric values or a component result as described in Details.
#'
#' @examples
#' storage_from_capacity(FlodeExponentialCapacity(100), c = 50)
#'
#' @references Moore (2007), doi:10.5194/hess-11-483-2007.
#' @export
storage_from_capacity <- S7::new_generic("storage_from_capacity", "x")
#' Capacity from storage
#'
#' Call capacity_from_storage(x, s), where 0 <= s <= Smax. Unbounded laws return Inf at Smax.
#'
#' @param x An S7 capacity, routing, or recharge component, as required by the generic.
#' @param ... Method arguments: see Details for the component-specific calling convention.
#'
#' @return Numeric values or a component result as described in Details.
#'
#' @examples
#' capacity_from_storage(FlodeExponentialCapacity(100), s = 50)
#'
#' @references Moore (2007), doi:10.5194/hess-11-483-2007.
#' @export
capacity_from_storage <- S7::new_generic("capacity_from_storage", "x")

S7::method(capacity_cdf, FlodeParetoCapacity) <- function(x, c) {
  .capacity_x(c)
  if (length(c) ==
        0L) {
    return(numeric())
  }
  if (x@b == 0) {
    return(as.numeric(c >= x@cmax))
  }
  z <- pmin(1, pmax(0, (c - x@cmin) / (x@cmax - x@cmin)))
  -expm1(x@b * log1p(-z))
}
S7::method(capacity_pdf, FlodeParetoCapacity) <- function(x, c) {
  .capacity_x(c)
  if (length(c) ==
        0L) {
    return(numeric())
  }
  .check(x@b > 0, "b=0 is a point mass at cmax; it has no ordinary density")
  ans <- numeric(length(c))
  i <- c >= x@cmin & c <= x@cmax
  ans[i] <- x@b / (x@cmax - x@cmin) * ((x@cmax - c[i]) / (x@cmax - x@cmin))^(x@b - 1)
  ans
}
S7::method(capacity_mean, FlodeParetoCapacity) <- function(x) {
  x@cmin +
    (x@cmax - x@cmin) / (x@b + 1)
}
S7::method(storage_from_capacity, FlodeParetoCapacity) <- function(x, c) {
  .capacity_x(c)
  if (length(c) ==
        0L) {
    return(numeric())
  }
  z <- pmin(1, pmax(0, (c - x@cmin) / (x@cmax - x@cmin)))
  out <- x@cmin + (capacity_mean(x) -
                     x@cmin) * (-expm1((x@b + 1) * log1p(-z)))
  ifelse(c < x@cmin, c, out)
}
