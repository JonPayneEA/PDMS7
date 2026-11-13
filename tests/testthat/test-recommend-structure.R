# Tests for recommend_structure() and its choice rule.

choice_table <- function(validation, at_bound = FALSE, peak = NA_real_, parameters = 7L,
                         structure = c("standard", "split", "demand")) {
  data.frame(structure = structure, parameters = parameters, validation = validation,
             at_bound = at_bound, median_abs_peak_error = peak)
}

# Guards: the incumbent is kept when it is among the equally good
test_that("a tie keeps the incumbent", {
  out <- .choose_structure(choice_table(c(0.90, 0.91, 0.80)), "standard", 0.02, "higher")
  expect_equal(out$choice, "standard")
  expect_setequal(out$equally_good, c("standard", "split"))
  expect_match(out$reason, "cannot justify a change")
})

# Guards: a clear winner replaces the incumbent
test_that("a clear winner is chosen", {
  out <- .choose_structure(choice_table(c(0.80, 0.91, 0.70)), "standard", 0.02, "higher")
  expect_equal(out$choice, "split")
  expect_match(out$reason, "by more than 0.02")
})

# Guards: structures at a bound are set aside unless all are; ties break on events, then size
test_that("bounds, events and parameters break the choice", {
  aside <- .choose_structure(choice_table(c(0.80, 0.95, 0.94), at_bound = c(FALSE, TRUE, FALSE)),
                             "standard", 0.02, "higher")
  expect_equal(aside$choice, "demand")
  expect_match(aside$reason, "Set aside with a parameter at a bound: split")
  all_bound <- .choose_structure(choice_table(c(0.80, 0.95, 0.70), at_bound = TRUE),
                                 "standard", 0.02, "higher")
  expect_equal(all_bound$choice, "split")
  events <- .choose_structure(choice_table(c(0.70, 0.95, 0.94), peak = c(NA, 0.3, 0.1)),
                              "standard", 0.02, "higher")
  expect_equal(events$choice, "demand")
  sizes <- .choose_structure(choice_table(c(0.70, 0.95, 0.94), parameters = c(7L, 7L, 9L)),
                             "standard", 0.02, "higher")
  expect_equal(sizes$choice, "split")
  lower <- .choose_structure(choice_table(c(0.5, 0.2, 0.9)), "standard", 0.02, "lower")
  expect_equal(lower$choice, "split")
})

# Guards: the variants change one component and keep the incumbent's own values
test_that("component variants change one slot", {
  base <- pdm_presets("standard")
  base$recharge$kg <- 777
  v <- .component_variants(base, "recharge")
  expect_named(v, c("standard", "split", "demand"))
  expect_equal(v$standard$recharge$kg, 777)
  expect_equal(v$split$recharge$type, "split")
  expect_identical(v$split$surface, base$surface)
  expect_equal(.component_type(base, "groundwater"), "cubic")
  expect_named(.component_variants(base, "distribution"),
               c("pareto", "rectangular", "triangular", "exponential", "lognormal"))
})

# Guards: a recommendation runs its comparisons, chooses, and writes its reasons to the log
test_that("recommend_structure chooses and logs a note per step", {
  p <- new_project() # nolint: object_usage_linter.
  rec <- recommend_structure(p$folder, components = c("recharge", "groundwater"), starts = 1,
                             control = list(maxit = 3), n_events = 3,
                             reasoning = "Testing the recommendation.")
  expect_s3_class(rec, "pdm_structure_recommendation")
  expect_named(rec$steps, c("recharge", "groundwater"))
  expect_true(rec$steps$recharge$choice %in% c("standard", "split", "demand"))
  expect_true(all(c("at_bound", "equally_good", "median_abs_peak_error") %in%
                    names(rec$steps$recharge$table)))
  expect_equal(read_entry(p$folder, rec$entry)$type, "auto_calibration")
  notes <- read_project(p$folder)$entries
  expect_equal(sum(notes$type == "note"), 2L)
  expect_output(print(rec), "Structure recommendation")
  expect_true(all(verify_project(p$folder)$ok))
  expect_error(recommend_structure(p$folder, components = "routing", reasoning = "x"),
               "components")
})

# Guards: the report's decision diagram and run totals are rebuilt from the log alone, and agree
# with the recommendation and with the runs each calibration recorded
test_that("the structure decisions and run totals are rebuilt from the log", {
  p <- new_project() # nolint: object_usage_linter.
  rec <- recommend_structure(p$folder, components = c("recharge", "groundwater"), starts = 1,
                             control = list(maxit = 3), n_events = 3,
                             reasoning = "Testing the decisions.")
  entries <- .read_entries(p$folder)
  steps <- .structure_decisions(p$folder, entries)
  expect_identical(vapply(steps, `[[`, "", "component"), c("recharge", "groundwater"))
  expect_identical(vapply(steps, `[[`, "", "choice"),
                   c(rec$steps$recharge$choice, rec$steps$groundwater$choice))
  expect_identical(steps[[1]]$reason, rec$steps$recharge$reason)
  expect_identical(steps[[1]]$incumbent, "standard")
  expect_identical(steps[[1]]$table$at_bound[order(steps[[1]]$table$structure)],
                   rec$steps$recharge$table$at_bound[order(rec$steps$recharge$table$structure)])
  expect_true(nzchar(.decision_tag(steps[[1]]$reason)))
  file <- tempfile(fileext = ".png")
  grDevices::png(file)
  expect_silent(.plot_decisions(steps, list(stages = character(0), candidate = NULL)))
  grDevices::dev.off()
  unlink(file)
  totals <- .run_totals(entries)
  autos <- Filter(function(e) e$type == "auto_calibration", entries)
  expect_identical(totals$part, c("Structure step: Recharge", "Structure step: Groundwater store",
                                  "Total"))
  expect_equal(totals$model_runs[3], sum(vapply(autos, function(e) e$evaluations, numeric(1))))
  expect_equal(totals$calibrations[3], length(autos))
  expect_true(all(totals$elapsed >= 0))
  blocks <- .rpt_run_totals(entries)
  expect_identical(blocks[[1]]$text, "Run totals")
})

# Guards: peak errors of -50% and +50% do not cancel; the tie-break uses their size
test_that("the event summary gives the median size of the peak errors", {
  events <- data.frame(period = "validation", use = TRUE, observed_peak = 4:1,
                       peak_error = c(-0.5, 0.5, -0.5, 0.5), timing_error_h = 0, nse = 0.8)
  s <- .event_summary(events, "validation", top = 4)
  expect_equal(s$median_peak_error, 0)
  expect_equal(s$median_abs_peak_error, 0.5)
  steady <- transform(events, peak_error = c(-0.1, 0.1, -0.1, 0.1))
  expect_lt(.event_summary(steady, "validation", 4)$median_abs_peak_error,
            s$median_abs_peak_error)
})
