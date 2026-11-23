
circDiff_abs <- function(a, b) {
  d <- abs(a - b)
  valid <- !is.na(d)
  d[valid & d > 180] <- 360 - d[valid & d > 180]
  return(d)
}



run_models <- function(
    formula_string,
    predictors,
    data,
    control = FALSE,
    sensitivity = FALSE,
    BF = FALSE,
    z_scale = TRUE
) {
  
  # ==========================================================
  # 0. SETUP
  # ==========================================================
  
  data <- data %>%
    mutate(subject_id = as.character(subject_id))
  
  if (anyNA(data$subject_id)) {
    stop("'subject_id' contains missing values.")
  }
  
  if (!grepl("\\bpredictor\\b", formula_string, perl = TRUE)) {
    stop("formula_string must contain the placeholder 'predictor'.")
  }
  
  if (!is.logical(z_scale) || length(z_scale) != 1) {
    stop("'z_scale' must be TRUE or FALSE.")
  }
  
  if (BF && !requireNamespace("BayesFactor", quietly = TRUE)) {
    stop("Package 'BayesFactor' must be installed when BF = TRUE.")
  }
  
  
  # ----------------------------------------------------------
  # Check controls and remove participants with missing controls
  #
  # IMPORTANT:
  # Controls are NOT scaled here.
  # Scaling happens later in each final analytic sample.
  # ----------------------------------------------------------
  
  if (control) {
    
    control_vars <- c(
      "gender",
      "age",
      "education"
    )
    
    missing_controls <- setdiff(
      control_vars,
      names(data)
    )
    
    if (length(missing_controls) > 0) {
      
      stop(
        paste0(
          "Control variable(s) missing from data: ",
          paste(
            missing_controls,
            collapse = ", "
          )
        )
      )
    }
    
    
    if (
      !is.numeric(data$age) ||
      !is.numeric(data$education)
    ) {
      
      stop(
        "'age' and 'education' must be numeric when control = TRUE."
      )
    }
    
    
    # Controls should be participant-level.
    control_check <- data %>%
      group_by(subject_id) %>%
      summarise(
        across(
          all_of(control_vars),
          ~ n_distinct(
            .x,
            na.rm = TRUE
          ),
          .names = "n_{.col}"
        ),
        .groups = "drop"
      )
    
    
    if (
      any(
        as.matrix(
          control_check[
            ,
            -1,
            drop = FALSE
          ]
        ) > 1
      )
    ) {
      
      stop(
        paste0(
          "Control variables must have at most one ",
          "non-missing value per participant."
        )
      )
    }
    
    
    # Exclude whole participants if any control is missing
    # or age/education are non-finite.
    invalid_control_ids <- data %>%
      filter(
        is.na(gender) |
          is.na(age) |
          is.na(education) |
          !is.finite(age) |
          !is.finite(education)
      ) %>%
      pull(subject_id) %>%
      unique()
    
    
    if (length(invalid_control_ids) > 0) {
      
      data <- data %>%
        filter(
          !subject_id %in%
            invalid_control_ids
        )
      
      
      message(
        paste0(
          "Note: ",
          length(invalid_control_ids),
          " participant(s) with missing/non-finite control ",
          "data were excluded before all analyses."
        )
      )
    }
    
    
    message(
      paste0(
        "Note: Age and education are z-standardized ",
        "across participants within each final analytic sample."
      )
    )
  }
  
  
  # ----------------------------------------------------------
  # Outcome expression
  #
  # scale(mean_inf) -> mean_inf
  # log(lr + 1)     -> log(lr + 1)
  #
  # Actual standardization occurs later.
  # ----------------------------------------------------------
  
  original_formula <- as.formula(
    formula_string
  )
  
  outcome_expr <- original_formula[[2]]
  
  
  if (
    is.call(outcome_expr) &&
    identical(
      as.character(
        outcome_expr[[1]]
      ),
      "scale"
    )
  ) {
    
    outcome_expr <- outcome_expr[[2]]
  }
  
  
  outcome_label <- paste(
    deparse(
      outcome_expr
    ),
    collapse = ""
  )
  
  
  outcome_values <- eval(
    outcome_expr,
    envir = data,
    enclos = parent.frame()
  )
  
  
  if (!is.numeric(outcome_values)) {
    stop(
      "Outcome must evaluate to a numeric variable."
    )
  }
  
  
  data$.outcome_unscaled <- as.numeric(
    outcome_values
  )
  
  
  message(
    paste0(
      "Note: Outcome is always z-standardized ",
      "within the final analytic sample."
    )
  )
  
  
  has_noise_condition <-
    "Noise_Condition" %in%
    names(data)
  
  
  # ==========================================================
  # 1. OUTLIERS
  # ==========================================================
  
  if (has_noise_condition) {
    
    participant_outcomes <- data %>%
      group_by(
        subject_id,
        Noise_Condition
      ) %>%
      summarise(
        Mean_Outcome = mean(
          .outcome_unscaled,
          na.rm = TRUE
        ),
        .groups = "drop"
      ) %>%
      filter(
        is.finite(
          Mean_Outcome
        )
      )
    
    
    outlier_df <- participant_outcomes %>%
      group_by(
        Noise_Condition
      ) %>%
      rstatix::identify_outliers(
        Mean_Outcome
      ) %>%
      ungroup()
    
  } else {
    
    participant_outcomes <- data %>%
      group_by(subject_id) %>%
      summarise(
        Mean_Outcome = mean(
          .outcome_unscaled,
          na.rm = TRUE
        ),
        .groups = "drop"
      ) %>%
      filter(
        is.finite(
          Mean_Outcome
        )
      )
    
    
    outlier_df <- participant_outcomes %>%
      rstatix::identify_outliers(
        Mean_Outcome
      )
  }
  
  
  if (nrow(outlier_df) > 0) {
    
    outliers <- outlier_df %>%
      mutate(
        Outcome = outcome_label,
        
        Outlier = if_else(
          is.extreme,
          "Extreme",
          "Moderate"
        ),
        
        Outlier_Method =
          paste0(
            "IQR rule: outside 1.5×IQR fences = outlier; ",
            "outside 3×IQR fences = extreme"
          )
      )
    
    
    if (!has_noise_condition) {
      
      outliers <- outliers %>%
        mutate(
          Noise_Condition =
            NA_character_
        )
    }
    
    
    outliers <- outliers %>%
      select(
        subject_id,
        Noise_Condition,
        Outcome,
        Mean_Outcome,
        Outlier,
        Outlier_Method
      )
    
    
    extreme_ids <- outliers %>%
      filter(
        Outlier == "Extreme"
      ) %>%
      pull(subject_id) %>%
      unique()
    
    
    all_outlier_ids <- outliers %>%
      pull(subject_id) %>%
      unique()
    
    
    moderate_only_ids <- setdiff(
      all_outlier_ids,
      extreme_ids
    )
    
  } else {
    
    outliers <- tibble(
      subject_id = character(),
      Noise_Condition = character(),
      Outcome = character(),
      Mean_Outcome = numeric(),
      Outlier = character(),
      Outlier_Method = character()
    )
    
    
    extreme_ids <- character()
    all_outlier_ids <- character()
    moderate_only_ids <- character()
  }
  
  
  # ==========================================================
  # 2. SENSITIVITY SAMPLES
  # ==========================================================
  
  samples <- list(
    "A: Full sample" = data
  )
  
  
  if (sensitivity) {
    
    if (length(all_outlier_ids) == 0) {
      
      message(
        paste0(
          "Note: No extreme or moderate outliers detected; ",
          "sensitivity samples B and C were skipped because ",
          "they are identical to the full sample."
        )
      )
      
    } else {
      
      
      if (length(extreme_ids) > 0) {
        
        samples[["B: Without extreme outliers"]] <- data %>%
          filter(
            !subject_id %in%
              extreme_ids
          )
        
      } else {
        
        message(
          paste0(
            "Note: No extreme outliers detected; ",
            "sensitivity sample B was skipped because ",
            "it is identical to the full sample."
          )
        )
      }
      
      
      if (length(moderate_only_ids) > 0) {
        
        samples[["C: Without all outliers"]] <- data %>%
          filter(
            !subject_id %in%
              all_outlier_ids
          )
        
      } else if (length(extreme_ids) > 0) {
        
        message(
          paste0(
            "Note: No additional moderate-only outliers detected; ",
            "sensitivity sample C was skipped because ",
            "it is identical to sample B."
          )
        )
      }
    }
  }
  
  
  # ==========================================================
  # 3. FORMULA HELPERS
  # ==========================================================
  
  add_controls <- function(
    frml,
    standardized = FALSE
  ) {
    
    if (!control) {
      return(frml)
    }
    
    
    if (standardized) {
      
      update(
        frml,
        . ~ . +
          gender +
          .age_z +
          .education_z
      )
      
    } else {
      
      # Raw controls used for complete-case determination.
      update(
        frml,
        . ~ . +
          gender +
          age +
          education
      )
    }
  }
  
  
  make_formula <- function(
    predictor_column,
    outcome_column,
    standardized_controls = FALSE
  ) {
    
    frml <- as.formula(
      gsub(
        "\\bpredictor\\b",
        predictor_column,
        formula_string,
        perl = TRUE
      )
    )
    
    
    frml[[2]] <- as.name(
      outcome_column
    )
    
    
    add_controls(
      frml,
      standardized =
        standardized_controls
    )
  }
  
  
  # ==========================================================
  # 4. BAYES FACTOR HELPERS
  # ==========================================================
  
  get_bf_random_structure <- function(
    frml
  ) {
    
    bars <- lme4::findbars(
      lme4::expandDoubleVerts(
        frml
      )
    )
    
    
    if (length(bars) == 0) {
      
      return(
        list(
          terms = character(),
          groups = character()
        )
      )
    }
    
    
    random_terms <- character()
    random_groups <- character()
    
    
    for (bar in bars) {
      
      group_vars <- all.vars(
        bar[[3]]
      )
      
      
      if (length(group_vars) != 1) {
        
        stop(
          paste0(
            "BF calculation requires simple grouping ",
            "variables such as (1 | subject_id) or ",
            "(x | subject_id)."
          )
        )
      }
      
      
      group <- group_vars[1]
      
      random_groups <- c(
        random_groups,
        group
      )
      
      
      random_lhs <- terms(
        as.formula(
          paste(
            "~",
            paste(
              deparse(
                bar[[2]]
              ),
              collapse = ""
            )
          )
        )
      )
      
      
      if (
        attr(
          random_lhs,
          "intercept"
        ) == 1
      ) {
        
        random_terms <- c(
          random_terms,
          group
        )
      }
      
      
      slope_terms <- attr(
        random_lhs,
        "term.labels"
      )
      
      
      if (length(slope_terms) > 0) {
        
        random_terms <- c(
          random_terms,
          paste0(
            slope_terms,
            ":",
            group
          )
        )
      }
    }
    
    
    list(
      terms =
        unique(
          random_terms
        ),
      
      groups =
        unique(
          random_groups
        )
    )
  }
  
  
  calculate_bf <- function(
    frml,
    target_term,
    bf_data
  ) {
    
    fixed_terms <- attr(
      terms(
        lme4::nobars(
          frml
        )
      ),
      "term.labels"
    )
    
    
    random_structure <- get_bf_random_structure(
      frml
    )
    
    
    # --------------------------------------------------------
    # Main predictor
    # --------------------------------------------------------
    
    if (
      identical(
        target_term,
        ".predictor_model"
      )
    ) {
      
      predictor_related <- vapply(
        fixed_terms,
        function(term) {
          
          ".predictor_model" %in%
            all.vars(
              as.formula(
                paste(
                  "~",
                  term
                )
              )
            )
        },
        logical(1)
      )
      
      
      base_terms <- fixed_terms[
        !predictor_related
      ]
      
      
      numerator_fixed <- c(
        base_terms,
        ".predictor_model"
      )
      
      
      denominator_fixed <-
        base_terms
      
      
      # --------------------------------------------------------
      # Interaction
      # --------------------------------------------------------
      
    } else {
      
      numerator_fixed <-
        fixed_terms
      
      
      denominator_fixed <- setdiff(
        fixed_terms,
        target_term
      )
    }
    
    
    numerator_terms <- unique(
      c(
        numerator_fixed,
        random_structure$terms
      )
    )
    
    
    denominator_terms <- unique(
      c(
        denominator_fixed,
        random_structure$terms
      )
    )
    
    
    build_bf_formula <- function(
    model_terms
    ) {
      
      rhs <- if (
        length(model_terms) == 0
      ) {
        
        "1"
        
      } else {
        
        paste(
          model_terms,
          collapse = " + "
        )
      }
      
      
      as.formula(
        paste(
          ".outcome_z ~",
          rhs
        )
      )
    }
    
    
    numerator_formula <- build_bf_formula(
      numerator_terms
    )
    
    
    denominator_formula <- build_bf_formula(
      denominator_terms
    )
    
    
    which_random <- if (
      length(
        random_structure$groups
      ) == 0
    ) {
      
      NULL
      
    } else {
      
      random_structure$groups
    }
    
    
    for (
      group in
      random_structure$groups
    ) {
      
      bf_data[[group]] <- factor(
        bf_data[[group]]
      )
    }
    
    
    numerator_bf <- BayesFactor::lmBF(
      formula = numerator_formula,
      data = bf_data,
      whichRandom = which_random,
      progress = FALSE
    )
    
    
    if (length(denominator_terms) == 0) {
      
      bf_comparison <-
        numerator_bf
      
    } else {
      
      denominator_bf <- BayesFactor::lmBF(
        formula = denominator_formula,
        data = bf_data,
        whichRandom = which_random,
        progress = FALSE
      )
      
      
      bf_comparison <-
        numerator_bf /
        denominator_bf
    }
    
    
    bf_extract <- BayesFactor::extractBF(
      bf_comparison
    )
    
    
    tibble(
      BF =
        bf_extract$bf[1],
      
      BF_error_percent =
        100 *
        bf_extract$error[1],
      
      BF_comparison = if_else(
        identical(
          target_term,
          ".predictor_model"
        ),
        "Predictor vs reduced model",
        "Interaction vs model without interaction"
      )
    )
  }
  
  
  # ==========================================================
  # 5. RUN MODELS
  # ==========================================================
  
  results_all <- list()
  sample_info_all <- list()
  
  
  for (v in predictors) {
    
    if (!v %in% names(data)) {
      
      stop(
        paste0(
          "Predictor '",
          v,
          "' not found in data."
        )
      )
    }
    
    
    predictor_level_reported <-
      NULL
    
    
    for (
      sample_name in
      names(samples)
    ) {
      
      sample_data <-
        samples[[sample_name]]
      
      
      # ------------------------------------------------------
      # Predictor at original observational level
      # ------------------------------------------------------
      
      current_data <- sample_data %>%
        mutate(
          .predictor_raw =
            .data[[v]]
        )
      
      
      # ------------------------------------------------------
      # Determine exact complete analytic observations
      #
      # RAW controls are used here because they have not yet
      # been standardized.
      # ------------------------------------------------------
      
      screening_formula <- make_formula(
        predictor_column =
          ".predictor_raw",
        
        outcome_column =
          ".outcome_unscaled",
        
        standardized_controls =
          FALSE
      )
      
      
      required_vars <- all.vars(
        screening_formula
      )
      
      
      missing_vars <- setdiff(
        required_vars,
        names(
          current_data
        )
      )
      
      
      if (length(missing_vars) > 0) {
        
        stop(
          paste0(
            "Variables missing from data: ",
            paste(
              missing_vars,
              collapse = ", "
            )
          )
        )
      }
      
      
      keep <- complete.cases(
        current_data[
          required_vars
        ]
      )
      
      
      # Remove +/-Inf as well as NA.
      for (nm in required_vars) {
        
        if (
          is.numeric(
            current_data[[nm]]
          )
        ) {
          
          keep <- keep &
            is.finite(
              current_data[[nm]]
            )
        }
      }
      
      
      model_data <- current_data[
        keep,
        ,
        drop = FALSE
      ]
      
      
      if (nrow(model_data) == 0) {
        
        stop(
          paste0(
            "No complete observations remain for predictor '",
            v,
            "', sample '",
            sample_name,
            "'."
          )
        )
      }
      
      
      # ======================================================
      # PREDICTOR TYPE
      # ======================================================
      
      predictor_numeric <-
        is.numeric(
          model_data$.predictor_raw
        )
      
      
      predictor_check <- model_data %>%
        group_by(
          subject_id
        ) %>%
        summarise(
          n_values = n_distinct(
            .predictor_raw
          ),
          .groups = "drop"
        )
      
      
      predictor_level <- if (
        any(
          predictor_check$n_values > 1
        )
      ) {
        
        "Within-subjects"
        
      } else {
        
        "Between-subjects"
      }
      
      
      # ------------------------------------------------------
      # Scaling information
      # ------------------------------------------------------
      
      if (
        is.null(
          predictor_level_reported
        )
      ) {
        
        predictor_level_reported <-
          predictor_level
        
        
        if (
          z_scale &&
          predictor_numeric
        ) {
          
          if (
            predictor_level ==
            "Between-subjects"
          ) {
            
            message(
              paste0(
                "Note: Between-subjects predictor '",
                v,
                "' is z-standardized across participants ",
                "within each final analytic sample."
              )
            )
            
          } else {
            
            message(
              paste0(
                "Note: Within-subjects predictor '",
                v,
                "' is z-standardized within participants."
              )
            )
          }
          
        } else if (
          z_scale &&
          !predictor_numeric
        ) {
          
          message(
            paste0(
              "Note: Categorical ",
              tolower(
                predictor_level
              ),
              " predictor '",
              v,
              "' is not standardized."
            )
          )
        }
        
        
      } else if (
        predictor_level !=
        predictor_level_reported
      ) {
        
        warning(
          paste0(
            "Predictor '",
            v,
            "' was classified as ",
            predictor_level_reported,
            " in the full sample but as ",
            predictor_level,
            " in sample '",
            sample_name,
            "'."
          )
        )
      }
      
      
      # ======================================================
      # ADDITIONAL EXCLUSIONS NEEDED BEFORE SCALING
      # ======================================================
      
      if (
        z_scale &&
        predictor_numeric &&
        predictor_level ==
        "Within-subjects"
      ) {
        
        predictor_sd <- model_data %>%
          group_by(
            subject_id
          ) %>%
          summarise(
            predictor_sd =
              sd(
                .predictor_raw
              ),
            .groups = "drop"
          )
        
        
        unscalable_ids <- predictor_sd %>%
          filter(
            !is.finite(
              predictor_sd
            ) |
              predictor_sd == 0
          ) %>%
          pull(
            subject_id
          )
        
        
        if (length(unscalable_ids) > 0) {
          
          warning(
            paste0(
              length(
                unscalable_ids
              ),
              " participant(s) excluded for predictor '",
              v,
              "' in sample '",
              sample_name,
              "' because within-person SD was zero or undefined."
            )
          )
          
          
          model_data <- model_data %>%
            filter(
              !subject_id %in%
                unscalable_ids
            )
        }
      }
      
      
      if (nrow(model_data) == 0) {
        
        stop(
          paste0(
            "No observations remain for predictor '",
            v,
            "', sample '",
            sample_name,
            "' after preprocessing."
          )
        )
      }
      
      
      # ======================================================
      # STANDARDIZATION
      #
      # ALL scaling occurs only now, after:
      #
      # - control-NA exclusions
      # - sensitivity/outlier exclusions
      # - model-specific NA/non-finite exclusions
      # - zero-SD within-person predictor exclusions
      # ======================================================
      
      
      # ------------------------------------------------------
      # Outcome: always standardized across final observations
      # ------------------------------------------------------
      
      model_data$.outcome_z <- as.numeric(
        base::scale(
          model_data$.outcome_unscaled
        )
      )
      
      
      if (
        any(
          !is.finite(
            model_data$.outcome_z
          )
        )
      ) {
        
        stop(
          paste0(
            "Cannot standardize outcome '",
            outcome_label,
            "' in sample '",
            sample_name,
            "': SD is zero or undefined."
          )
        )
      }
      
      
      # ------------------------------------------------------
      # Focal predictor
      # ------------------------------------------------------
      
      if (
        z_scale &&
        predictor_numeric
      ) {
        
        
        # ====================================================
        # Between-subjects predictor
        # ====================================================
        
        if (
          predictor_level ==
          "Between-subjects"
        ) {
          
          predictor_values <- model_data %>%
            select(
              subject_id,
              .predictor_raw
            ) %>%
            distinct()
          
          
          predictor_values$.predictor_model <- as.numeric(
            base::scale(
              predictor_values$.predictor_raw
            )
          )
          
          
          if (
            any(
              !is.finite(
                predictor_values$.predictor_model
              )
            )
          ) {
            
            stop(
              paste0(
                "Cannot standardize predictor '",
                v,
                "' in sample '",
                sample_name,
                "': SD is zero or undefined."
              )
            )
          }
          
          
          model_data <- model_data %>%
            select(
              -.predictor_raw
            ) %>%
            left_join(
              predictor_values %>%
                select(
                  subject_id,
                  .predictor_model
                ),
              by = "subject_id"
            )
          
          
          # ====================================================
          # Within-subjects predictor
          # ====================================================
          
        } else {
          
          model_data$.predictor_model <- ave(
            model_data$.predictor_raw,
            model_data$subject_id,
            FUN = function(x) {
              as.numeric(
                base::scale(
                  x
                )
              )
            }
          )
          
          
          model_data <- model_data %>%
            select(
              -.predictor_raw
            )
        }
        
        
        # ======================================================
        # Predictor left unchanged
        # ======================================================
        
      } else {
        
        model_data$.predictor_model <-
          model_data$.predictor_raw
        
        
        model_data <- model_data %>%
          select(
            -.predictor_raw
          )
      }
      
      
      # ------------------------------------------------------
      # Controls
      #
      # Scale age and education NOW, using the exact same
      # final participant sample entering this model.
      # ------------------------------------------------------
      
      if (control) {
        
        control_values <- model_data %>%
          select(
            subject_id,
            age,
            education
          ) %>%
          distinct()
        
        
        control_values$.age_z <- as.numeric(
          base::scale(
            control_values$age
          )
        )
        
        
        control_values$.education_z <- as.numeric(
          base::scale(
            control_values$education
          )
        )
        
        
        if (
          any(
            !is.finite(
              control_values$.age_z
            )
          )
        ) {
          
          stop(
            paste0(
              "Cannot standardize age in sample '",
              sample_name,
              "': SD is zero or undefined."
            )
          )
        }
        
        
        if (
          any(
            !is.finite(
              control_values$.education_z
            )
          )
        ) {
          
          stop(
            paste0(
              "Cannot standardize education in sample '",
              sample_name,
              "': SD is zero or undefined."
            )
          )
        }
        
        
        model_data <- model_data %>%
          left_join(
            control_values %>%
              select(
                subject_id,
                .age_z,
                .education_z
              ),
            by = "subject_id"
          )
      }
      
      
      # ======================================================
      # FINAL MODEL FORMULA
      # ======================================================
      
      frml <- make_formula(
        predictor_column =
          ".predictor_model",
        
        outcome_column =
          ".outcome_z",
        
        standardized_controls =
          TRUE
      )
      
      
      has_random <-
        length(
          lme4::findbars(
            frml
          )
        ) > 0
      
      
      # ======================================================
      # LMM
      # ======================================================
      
      if (has_random) {
        
        mod <- lmerTest::lmer(
          frml,
          data = model_data,
          REML = TRUE,
          na.action = na.fail,
          control = lme4::lmerControl(
            optimizer = "bobyqa"
          )
        )
        
        
        coef_table <- as.data.frame(
          coef(
            summary(
              mod,
              ddf =
                "Satterthwaite"
            )
          )
        ) %>%
          tibble::rownames_to_column(
            "Parameter"
          ) %>%
          rename(
            Coefficient = Estimate,
            SE = `Std. Error`,
            df = df,
            t = `t value`,
            p = `Pr(>|t|)`
          ) %>%
          mutate(
            CI_low =
              Coefficient -
              qt(
                .975,
                df
              ) *
              SE,
            
            CI_high =
              Coefficient +
              qt(
                .975,
                df
              ) *
              SE
          )
        
        
        model_type <-
          "LMM"
        
        
        test_name <-
          "Two-sided t-test (Satterthwaite)"
        
        
        singular <- lme4::isSingular(
          mod
        )
        
        
        # ======================================================
        # LM
        # ======================================================
        
      } else {
        
        mod <- stats::lm(
          frml,
          data = model_data,
          na.action = na.fail
        )
        
        
        lm_df <- stats::df.residual(
          mod
        )
        
        
        coef_table <- as.data.frame(
          coef(
            summary(
              mod
            )
          )
        ) %>%
          tibble::rownames_to_column(
            "Parameter"
          ) %>%
          rename(
            Coefficient = Estimate,
            SE = `Std. Error`,
            t = `t value`,
            p = `Pr(>|t|)`
          ) %>%
          mutate(
            df =
              lm_df,
            
            CI_low =
              Coefficient -
              qt(
                .975,
                df
              ) *
              SE,
            
            CI_high =
              Coefficient +
              qt(
                .975,
                df
              ) *
              SE
          )
        
        
        model_type <-
          "LM"
        
        
        test_name <-
          "Two-sided t-test (OLS)"
        
        
        singular <-
          NA
      }
      
      
      # ======================================================
      # MAP COEFFICIENTS TO TERMS
      # ======================================================
      
      model_matrix <- model.matrix(
        mod
      )
      
      
      assign_index <- attr(
        model_matrix,
        "assign"
      )
      
      
      term_labels <- attr(
        terms(
          lme4::nobars(
            frml
          )
        ),
        "term.labels"
      )
      
      
      mapped_terms <- rep(
        "(Intercept)",
        length(
          assign_index
        )
      )
      
      
      non_intercept <-
        assign_index > 0
      
      
      mapped_terms[
        non_intercept
      ] <- term_labels[
        assign_index[
          non_intercept
        ]
      ]
      
      
      term_map <- tibble(
        Parameter =
          colnames(
            model_matrix
          ),
        
        .term =
          mapped_terms
      )
      
      
      coef_table <- coef_table %>%
        left_join(
          term_map,
          by = "Parameter"
        ) %>%
        filter(
          !is.na(
            .term
          ),
          grepl(
            ".predictor_model",
            .term,
            fixed = TRUE
          )
        )
      
      
      if (nrow(coef_table) == 0) {
        
        stop(
          paste0(
            "No coefficient involving predictor '",
            v,
            "' was found."
          )
        )
      }
      
      
      if (predictor_numeric) {
        
        predictor_labels <- gsub(
          ":",
          "*",
          gsub(
            ".predictor_model",
            v,
            coef_table$.term,
            fixed = TRUE
          ),
          fixed = TRUE
        )
        
      } else {
        
        predictor_labels <- gsub(
          ".predictor_model",
          v,
          coef_table$Parameter,
          fixed = TRUE
        )
      }
      
      
      model_result <- coef_table %>%
        transmute(
          Sample =
            sample_name,
          
          Model =
            model_type,
          
          Predictor =
            predictor_labels,
          
          Coefficient =
            Coefficient,
          
          SE =
            SE,
          
          CI_low =
            CI_low,
          
          CI_high =
            CI_high,
          
          Test =
            test_name,
          
          t =
            t,
          
          df =
            df,
          
          p =
            p,
          
          .term =
            .term
        )
      
      
      # ======================================================
      # BAYES FACTORS
      # ======================================================
      
      if (BF) {
        
        bf_results <- lapply(
          unique(
            model_result$.term
          ),
          function(term) {
            
            tryCatch(
              
              calculate_bf(
                frml =
                  frml,
                
                target_term =
                  term,
                
                bf_data =
                  model_data
              ),
              
              error = function(e) {
                
                stop(
                  paste0(
                    "Bayes-factor calculation failed for predictor '",
                    v,
                    "', sample '",
                    sample_name,
                    "', term '",
                    term,
                    "': ",
                    conditionMessage(
                      e
                    )
                  )
                )
              }
            ) %>%
              mutate(
                .term =
                  term
              )
          }
        ) %>%
          bind_rows()
        
        
        model_result <- model_result %>%
          left_join(
            bf_results,
            by = ".term"
          )
      }
      
      
      model_result <- model_result %>%
        select(
          -.term
        )
      
      
      result_key <- paste(
        sample_name,
        v,
        sep = "_"
      )
      
      
      results_all[[result_key]] <-
        model_result
      
      
      # ======================================================
      # SAMPLE INFO
      # ======================================================
      
      sample_info_all[[result_key]] <- tibble(
        
        Sample =
          sample_name,
        
        Predictor =
          v,
        
        Model =
          model_type,
        
        N_model_subjects =
          n_distinct(
            model_data$subject_id
          ),
        
        N_subjects_model_excluded =
          n_distinct(
            sample_data$subject_id
          ) -
          n_distinct(
            model_data$subject_id
          ),
        
        Singular =
          singular
      )
    }
  }
  
  
  # ==========================================================
  # 6. COMBINE RESULTS
  # ==========================================================
  
  results <- bind_rows(
    results_all
  ) %>%
    group_by(
      Sample
    ) %>%
    mutate(
      
      stars = case_when(
        p < .001 ~ "***",
        p < .01 ~ "**",
        p < .05 ~ "*",
        TRUE ~ ""
      ),
      
      p_BH = p.adjust(
        p,
        method = "BH"
      ),
      
      stars_BH = case_when(
        p_BH < .001 ~ "***",
        p_BH < .01 ~ "**",
        p_BH < .05 ~ "*",
        TRUE ~ ""
      )
    ) %>%
    ungroup() %>%
    mutate(
      across(
        where(
          is.numeric
        ),
        ~ round(
          .x,
          3
        )
      )
    ) %>%
    select(
      Sample,
      Model,
      Predictor,
      Coefficient,
      SE,
      CI_low,
      CI_high,
      Test,
      t,
      df,
      p,
      stars,
      p_BH,
      stars_BH,
      any_of(
        c(
          "BF",
          "BF_error_percent",
          "BF_comparison"
        )
      )
    )
  
  
  # ==========================================================
  # 7. RETURN
  # ==========================================================
  
  list(
    results =
      results,
    
    outliers =
      outliers,
    
    sample_info =
      bind_rows(
        sample_info_all
      )
  )
}