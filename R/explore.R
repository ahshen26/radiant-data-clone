#' Explore and summarize data
#'
#' @details See \url{https://radiant-rstats.github.io/docs/data/explore.html} for an example in Radiant
#'
#' @param dataset Dataset to explore
#' @param vars (Numeric) variables to summarize
#' @param byvar Variable(s) to group data by
#' @param fun Functions to use for summarizing
#' @param top Use functions ("fun"), variables ("vars"), or group-by variables as column headers
#' @param tabfilt Expression used to filter the table (e.g., "Total > 10000")
#' @param tabsort Expression used to sort the table (e.g., "desc(Total)")
#' @param tabslice Expression used to filter table (e.g., "1:5")
#' @param nr Number of rows to display
#' @param data_filter Expression used to filter the dataset before creating the table (e.g., "price > 10000")
#' @param arr Expression to arrange (sort) the data on (e.g., "color, desc(price)")
#' @param rows Rows to select from the specified dataset
#' @param envir Environment to extract data from
#'
#' @return A list of all variables defined in the function as an object of class explore
#'
#' @examples
#' explore(diamonds, c("price", "carat")) %>% str()
#' explore(diamonds, "price:x")$tab
#' explore(diamonds, c("price", "carat"), byvar = "cut", fun = c("n_missing", "skew"))$tab
#'
#' @seealso See \code{\link{summary.explore}} to show summaries
#'
#' @export
explore <- function(dataset, vars = "", byvar = "", fun = c("mean", "sd"),
                    top = "fun", tabfilt = "", tabsort = "", tabslice = "",
                    nr = Inf, data_filter = "", arr = "", rows = NULL,
                    variable = "num", envir = parent.frame()) {
  tvars <- vars
  if (!is.empty(byvar)) tvars <- unique(c(tvars, byvar))

  df_name <- if (is_string(dataset)) dataset else deparse(substitute(dataset))
  dataset <- get_data(dataset, tvars, filt = data_filter, arr = arr, rows = rows, na.rm = FALSE, envir = envir)
  rm(tvars)

  ## in case : was used
  vars <- base::setdiff(colnames(dataset), byvar)

  if (variable == "cat") {
    # Handle categorical variable
    cat_levels <- levels(as.factor(dataset[[vars]]))
    count_table <- table(as.factor(dataset[[vars]]))
    cat_df <- data.frame(Level = names(count_table), Count = as.vector(count_table))
    cat_df$Percentage <- round((cat_df$Count / sum(cat_df$Count)) * 100, 2)

    result <- list(
      tab = cat_df,
      df_name = df_name,
      vars = vars,
      byvar = byvar,
      fun = fun,
      top = top,
      tabfilt = tabfilt,
      tabsort = tabsort,
      tabslice = tabslice,
      nr = nr,
      data_filter = data_filter,
      arr = arr,
      rows = rows,
      cat_levels = cat_levels
    ) %>% add_class("explore")

    return(result)
  }

  ## converting data as needed for summarization
  dc <- get_class(dataset)
  fixer <- function(x, fun = as_integer) {
    if (is.character(x) || is.Date(x)) {
      x <- rep(NA, length(x))
    } else if (is.factor(x)) {
      x_num <- sshhr(as.integer(as.character(x)))
      if (length(na.omit(x_num)) == 0) {
        x <- fun(x)
      } else {
        x <- x_num
      }
    }
    x
  }
  fixer_first <- function(x) {
    x <- fixer(x, function(x) as_integer(x == levels(x)[1]))
  }
  mean <- function(x, na.rm = TRUE) sshhr(base::mean(fixer_first(x), na.rm = na.rm))
  sum <- function(x, na.rm = TRUE) sshhr(base::sum(fixer_first(x), na.rm = na.rm))
  var <- function(x, na.rm = TRUE) sshhr(stats::var(fixer_first(x), na.rm = na.rm))
  sd <- function(x, na.rm = TRUE) sshhr(stats::sd(fixer_first(x), na.rm = na.rm))
  se <- function(x, na.rm = TRUE) sshhr(radiant.data::se(fixer_first(x), na.rm = na.rm))
  me <- function(x, na.rm = TRUE) sshhr(radiant.data::me(fixer_first(x), na.rm = na.rm))
  cv <- function(x, na.rm = TRUE) sshhr(radiant.data::cv(fixer_first(x), na.rm = na.rm))
  prop <- function(x, na.rm = TRUE) sshhr(radiant.data::prop(fixer_first(x), na.rm = na.rm))
  varprop <- function(x, na.rm = TRUE) sshhr(radiant.data::varprop(fixer_first(x), na.rm = na.rm))
  sdprop <- function(x, na.rm = TRUE) sshhr(radiant.data::sdprop(fixer_first(x), na.rm = na.rm))
  seprop <- function(x, na.rm = TRUE) sshhr(radiant.data::seprop(fixer_first(x), na.rm = na.rm))
  meprop <- function(x, na.rm = TRUE) sshhr(radiant.data::meprop(fixer_first(x), na.rm = na.rm))
  varpop <- function(x, na.rm = TRUE) sshhr(radiant.data::varpop(fixer_first(x), na.rm = na.rm))
  sdpop <- function(x, na.rm = TRUE) sshhr(radiant.data::sdpop(fixer_first(x), na.rm = na.rm))

  median <- function(x, na.rm = TRUE) sshhr(stats::median(fixer(x), na.rm = na.rm))
  min <- function(x, na.rm = TRUE) sshhr(base::min(fixer(x), na.rm = na.rm))
  max <- function(x, na.rm = TRUE) sshhr(base::max(fixer(x), na.rm = na.rm))
  p01 <- function(x, na.rm = TRUE) sshhr(radiant.data::p01(fixer(x), na.rm = na.rm))
  p025 <- function(x, na.rm = TRUE) sshhr(radiant.data::p025(fixer(x), na.rm = na.rm))
  p05 <- function(x, na.rm = TRUE) sshhr(radiant.data::p05(fixer(x), na.rm = na.rm))
  p10 <- function(x, na.rm = TRUE) sshhr(radiant.data::p10(fixer(x), na.rm = na.rm))
  p25 <- function(x, na.rm = TRUE) sshhr(radiant.data::p25(fixer(x), na.rm = na.rm))
  p75 <- function(x, na.rm = TRUE) sshhr(radiant.data::p75(fixer(x), na.rm = na.rm))
  p90 <- function(x, na.rm = TRUE) sshhr(radiant.data::p90(fixer(x), na.rm = na.rm))
  p95 <- function(x, na.rm = TRUE) sshhr(radiant.data::p95(fixer(x), na.rm = na.rm))
  p975 <- function(x, na.rm = TRUE) sshhr(radiant.data::p975(fixer(x), na.rm = na.rm))
  p99 <- function(x, na.rm = TRUE) sshhr(radiant.data::p99(fixer(x), na.rm = na.rm))
  skew <- function(x, na.rm = TRUE) sshhr(radiant.data::skew(fixer(x), na.rm = na.rm))
  kurtosi <- function(x, na.rm = TRUE) sshhr(radiant.data::kurtosi(fixer(x), na.rm = na.rm))

  isLogNum <- "logical" == dc & names(dc) %in% base::setdiff(vars, byvar)
  if (sum(isLogNum) > 0) {
    dataset[, isLogNum] <- select(dataset, which(isLogNum)) %>%
      mutate_all(as.integer)
    dc[isLogNum] <- "integer"
  }

  if (is.empty(byvar)) {
    byvar <- c()
    tab <- summarise_all(dataset, fun, na.rm = TRUE)
  } else {

    ## convert categorical variables to factors if needed
    ## needed to deal with empty/missing values
    dataset[, byvar] <- select_at(dataset, .vars = byvar) %>%
      mutate_all(~ empty_level(.))

    tab <- dataset %>%
      group_by_at(.vars = byvar) %>%
      summarise_all(fun, na.rm = TRUE)
  }

  ## adjust column names
  if (length(vars) == 1 || length(fun) == 1) {
    rng <- (length(byvar) + 1):ncol(tab)
    colnames(tab)[rng] <- paste0(vars, "_", fun)
    rm(rng)
  }

  ## setup regular expression to split variable/function column appropriately
  rex <- paste0("(.*?)_", glue('({glue_collapse(fun, "$|")}$)'))

  ## useful answer and comments: http://stackoverflow.com/a/27880388/1974918
  tab <- gather(tab, "variable", "value", !!-(seq_along(byvar))) %>%
    extract(variable, into = c("variable", "fun"), regex = rex) %>%
    mutate(fun = factor(fun, levels = !!fun), variable = factor(variable, levels = vars)) %>%
    spread("fun", "value")

  ## flip the table if needed
  if (top != "fun") {
    tab <- list(tab = tab, byvar = byvar, fun = fun) %>%
      flip(top)
  }

  nrow_tab <- nrow(tab)

  ## filtering the table if desired from Report > Rmd
  if (!is.empty(tabfilt)) {
    tab <- filter_data(tab, tabfilt)
  }

  ## sorting the table if desired from Report > Rmd
  if (!identical(tabsort, "")) {
    tabsort <- gsub(",", ";", tabsort)
    tab <- tab %>% arrange(!!!rlang::parse_exprs(tabsort))
  }

  ## ensure factors ordered as in the (sorted) table
  if (!is.empty(byvar) && top != "byvar") {
    for (i in byvar) tab[[i]] <- tab[[i]] %>% (function(x) factor(x, levels = unique(x)))
    rm(i)
  }

  ## frequencies converted to doubles during gather/spread above
  check_int <- function(x) {
    if (is.double(x) && length(na.omit(x)) > 0) {
      x_int <- sshhr(as.integer(round(x, .Machine$double.rounding)))
      if (isTRUE(all.equal(x, x_int, check.attributes = FALSE))) x_int else x
    } else {
      x
    }
  }

  tab <- ungroup(tab) %>% mutate_all(check_int)

  ## slicing the table if desired
  #if (!is.empty(tabslice)) {
    #tab <- tab %>%
     # slice_data(tabslice) %>%
     # droplevels()
 # }

  ## convert to data.frame to maintain attributes
  tab <- as.data.frame(tab, stringsAsFactors = FALSE)
  attr(tab, "radiant_nrow") <- nrow_tab
  if (!isTRUE(is.infinite(nr))) {
    ind <- if (nr > nrow(tab)) 1:nrow(tab) else 1:nr
    tab <- tab[ind, , drop = FALSE]
    rm(ind)
  }

  result <- list(
    tab = tab,
    dataset = dataset,
    df_name = df_name,
    vars = vars,
    byvar = byvar,
    fun = fun,
    top = top,
    tabfilt = tabfilt,
    tabsort = tabsort,
    tabslice = tabslice,
    nr = nr,
    data_filter = data_filter,
    arr = arr,
    rows = rows
  ) %>% add_class("explore")

  if (variable == "cat") {
    # Add the levels of the categorical variable to the result
    cat_levels <- levels(as.factor(dataset[[vars]]))
    result$cat_levels <- cat_levels
  }

  result
}

#' Summary method for the explore function
#'
#' @details See \url{https://radiant-rstats.github.io/docs/data/explore.html} for an example in Radiant
#'
#' @param object Return value from \code{\link{explore}}
#' @param dec Number of decimals to show
#' @param ... further arguments passed to or from other methods
#'
#' @examples
#' result <- explore(diamonds, "price:x")
#' summary(result)
#' result <- explore(diamonds, "price", byvar = "cut", fun = c("n_obs", "skew"))
#' summary(result)
#' explore(diamonds, "price:x", byvar = "color") %>% summary()
#'
#' @seealso \code{\link{explore}} to generate summaries
#'
#' @export
summary.explore <- function(object, dec = 3, ...) {
  cat("Explore\n")
  cat("Data        :", object$df_name, "\n")
  if (!is.empty(object$data_filter)) {
    cat("Filter      :", gsub("\\n", "", object$data_filter), "\n")
  }
  if (!is.empty(object$arr)) {
    cat("Arrange     :", gsub("\\n", "", object$arr), "\n")
  }
  if (!is.empty(object$rows)) {
    cat("Slice       :", gsub("\\n", "", object$rows), "\n")
  }
  if (!is.empty(object$tabfilt)) {
    cat("Table filter:", object$tabfilt, "\n")
  }
  if (!is.empty(object$tabsort[1])) {
    cat("Table sorted:", paste0(object$tabsort, collapse = ", "), "\n")
  }
  if (!is.empty(object$tabslice)) {
    cat("Table slice :", object$tabslice, "\n")
  }
  nr <- attr(object$tab, "radiant_nrow")
  if (!isTRUE(is.infinite(nr)) && !isTRUE(is.infinite(object$nr)) && object$nr < nr) {
    cat(paste0("Rows shown  : ", object$nr, " (out of ", nr, ")\n"))
  }
  if (!is.empty(object$byvar[1])) {
    cat("Grouped by  :", object$byvar, "\n")
  }
  cat("Functions   :", paste0(object$fun, collapse = ", "), "\n")
  cat("Top         :", c("fun" = "Function", "var" = "Variables", "byvar" = "Group by")[object$top], "\n")
  cat("\n")

  format_df(object$tab, dec = dec, mark = ",") %>%
    print(row.names = FALSE)
  invisible()
}

#' Deprecated: Store method for the explore function
#'
#' @details Return the summarized data. See \url{https://radiant-rstats.github.io/docs/data/explore.html} for an example in Radiant
#'
#' @param dataset Dataset
#' @param object Return value from \code{\link{explore}}
#' @param name Name to assign to the dataset
#' @param ... further arguments passed to or from other methods
#'
#' @seealso \code{\link{explore}} to generate summaries
#'
#' @export
store.explore <- function(dataset, object, name, ...) {
  if (missing(name)) {
    object$tab
  } else {
    stop(
      paste0(
        "This function is deprecated. Use the code below instead:\n\n",
        name, " <- ", deparse(substitute(object)), "$tab\nregister(\"",
        name, ")"
      ),
      call. = FALSE
    )
  }
}

#' Flip the DT table to put Function, Variable, or Group by on top
#'
#' @details See \url{https://radiant-rstats.github.io/docs/data/explore.html} for an example in Radiant
#'
#' @param expl Return value from \code{\link{explore}}
#' @param top The variable (type) to display at the top of the table ("fun" for Function, "var" for Variable, and "byvar" for Group by. "fun" is the default
#'
#' @examples
#' explore(diamonds, "price:x", top = "var") %>% summary()
#' explore(diamonds, "price", byvar = "cut", fun = c("n_obs", "skew"), top = "byvar") %>% summary()
#'
#' @seealso \code{\link{explore}} to calculate summaries
#' @seealso \code{\link{summary.explore}} to show summaries
#' @seealso \code{\link{dtab.explore}} to create the DT table
#'
#' @export
flip <- function(expl, top = "fun") {
  cvars <- expl$byvar %>%
    (function(x) if (is.empty(x[1])) character(0) else x)
  if (top[1] == "var") {
    expl$tab %<>% gather(".function", "value", !!-(1:(length(cvars) + 1))) %>%
      spread("variable", "value")
    expl$tab[[".function"]] %<>% factor(., levels = expl$fun)
  } else if (top[1] == "byvar" && length(cvars) > 0) {
    expl$tab %<>% gather(".function", "value", !!-(1:(length(cvars) + 1))) %>%
      spread(!!cvars[1], "value")
    expl$tab[[".function"]] %<>% factor(., levels = expl$fun)

    ## ensure we don't have invalid column names
    colnames(expl$tab) <- fix_names(colnames(expl$tab))
  }

  expl$tab
}

#' Make an interactive table of summary statistics
#'
#' @details See \url{https://radiant-rstats.github.io/docs/data/explore.html} for an example in Radiant
#'
#' @param object Return value from \code{\link{explore}}
#' @param dec Number of decimals to show
#' @param searchCols Column search and filter
#' @param order Column sorting
#' @param pageLength Page length
#' @param caption Table caption
#' @param ... further arguments passed to or from other methods
#'
#' @examples
#' \dontrun{
#' tab <- explore(diamonds, "price:x") %>% dtab()
#' tab <- explore(diamonds, "price", byvar = "cut", fun = c("n_obs", "skew"), top = "byvar") %>%
#'   dtab()
#' }
#'
#' @seealso \code{\link{pivotr}} to create a pivot table
#' @seealso \code{\link{summary.pivotr}} to show summaries
#'
#' @importFrom DT datatable formatRound JS
#' @export
dtab.explore <- function(object, dec = 3, searchCols = NULL,
                         order = NULL, pageLength = NULL,
                         caption = NULL, variable = "num", ...) {
  style <- if (exists("bslib_current_version") && "4" %in% bslib_current_version()) "bootstrap4" else "bootstrap"
  tab <- object$tab
  cn_all <- colnames(tab)
  isInt <- sapply(tab, is.integer)
  isDbl <- sapply(tab, is_double)
  dec <- ifelse(is.empty(dec) || dec < 0, 3, round(dec, 0))

  if (!is.empty(caption)) {
    ## from https://github.com/rstudio/DT/issues/630#issuecomment-461191378
    caption <- shiny::tags$caption(style = "caption-side: bottom; text-align: left; font-size:100%;", caption)
  }

  ## for display options see https://datatables.net/reference/option/dom
  dom <- if (nrow(tab) < 11) "t" else "ltip"
  fbox <- if (nrow(tab) > 5e6) "none" else list(position = "top")

  if (variable == "cat") {
    sketch_cat <- shiny::withTags(
      table(
        thead(
          tr(lapply(colnames(tab), th))
        )
      )
    )
    dt_cat_tab <- DT::datatable(
      tab,
      container = sketch_cat,
      caption = caption,
      selection = "none",
      rownames = FALSE,
      filter = fbox,
      ## must use fillContainer = FALSE to address
      ## see https://github.com/rstudio/DT/issues/367
      ## https://github.com/rstudio/DT/issues/379
      fillContainer = FALSE,
      style = style,
      options = list(
        dom = dom,
        stateSave = TRUE, ## store state
        searchCols = searchCols,
        order = order,
        columnDefs = list(list(orderSequence = c("desc", "asc"), targets = "_all")),
        autoWidth = TRUE,
        processing = FALSE,
        pageLength = {
          if (is.null(pageLength)) 10 else pageLength
        },
        lengthMenu = list(c(5, 10, 25, 50, -1), c("5", "10", "25", "50", "All"))
      ),
      ## https://github.com/rstudio/DT/issues/146#issuecomment-534319155
      callback = DT::JS('$(window).on("unload", function() { table.state.clear(); })')
    )
    return(dt_cat_tab)
  } else {
    sketch_num <- shiny::withTags(
      table(
        thead(
          tr(lapply(colnames(tab), th))
        )
      )
    )
    dt_num_tab <- DT::datatable(
      tab,
      container = sketch_num,
      caption = caption,
      selection = "none",
      rownames = FALSE,
      filter = fbox,
      ## must use fillContainer = FALSE to address
      ## see https://github.com/rstudio/DT/issues/367
      ## https://github.com/rstudio/DT/issues/379
      fillContainer = FALSE,
      style = style,
      options = list(
        dom = dom,
        stateSave = TRUE, ## store state
        searchCols = searchCols,
        order = order,
        columnDefs = list(list(orderSequence = c("desc", "asc"), targets = "_all")),
        autoWidth = TRUE,
        processing = FALSE,
        pageLength = {
          if (is.null(pageLength)) 10 else pageLength
        },
        lengthMenu = list(c(5, 10, 25, 50, -1), c("5", "10", "25", "All"))
      ),
      ## https://github.com/rstudio/DT/issues/146#issuecomment-534319155
      callback = DT::JS('$(window).on("unload", function() { table.state.clear(); })')
    )

    ## rounding as needed
    if (sum(isDbl) > 0) {
      dt_num_tab <- DT::formatRound(dt_num_tab, names(isDbl)[isDbl], dec)
    }
    if (sum(isInt) > 0) {
      dt_num_tab <- DT::formatRound(dt_num_tab, names(isInt)[isInt], 0)
    }

    ## see https://github.com/yihui/knitr/issues/1198
    dt_num_tab$dependencies <- c(
      list(rmarkdown::html_dependency_bootstrap("bootstrap")),
      dt_num_tab$dependencies
    )
    return(dt_num_tab)
  }
}


###########################################
## turn functions below into functional ...
###########################################

#' Number of observations
#' @param x Input variable
#' @param ... Additional arguments
#' @return number of observations
#' @examples
#' n_obs(c("a", "b", NA))
#'
#' @export
n_obs <- function(x, ...) length(x)

#' Number of missing values
#' @param x Input variable
#' @param ... Additional arguments
#' @return number of missing values
#' @examples
#' n_missing(c("a", "b", NA))
#'
#' @export
n_missing <- function(x, ...) sum(is.na(x))

#' Calculate percentiles
#' @param x Numeric vector
#' @param na.rm If TRUE missing values are removed before calculation
#' @examples
#' p01(0:100)
#'
#' @rdname percentiles
#' @export
p01 <- function(x, na.rm = TRUE) quantile(x, .01, na.rm = na.rm)

#' @rdname percentiles
#' @export
p025 <- function(x, na.rm = TRUE) quantile(x, .025, na.rm = na.rm)

#' @rdname percentiles
#' @export
p05 <- function(x, na.rm = TRUE) quantile(x, .05, na.rm = na.rm)

#' @rdname percentiles
#' @export
p10 <- function(x, na.rm = TRUE) quantile(x, .1, na.rm = na.rm)

#' @rdname percentiles
#' @export
p25 <- function(x, na.rm = TRUE) quantile(x, .25, na.rm = na.rm)

#' @rdname percentiles
#' @export
p75 <- function(x, na.rm = TRUE) quantile(x, .75, na.rm = na.rm)

#' @rdname percentiles
#' @export
p90 <- function(x, na.rm = TRUE) quantile(x, .90, na.rm = na.rm)

#' @rdname percentiles
#' @export
p95 <- function(x, na.rm = TRUE) quantile(x, .95, na.rm = na.rm)

#' @rdname percentiles
#' @export
p975 <- function(x, na.rm = TRUE) quantile(x, .975, na.rm = na.rm)

#' @rdname percentiles
#' @export
p99 <- function(x, na.rm = TRUE) quantile(x, .99, na.rm = na.rm)

#' Coefficient of variation
#' @param x Input variable
#' @param na.rm If TRUE missing values are removed before calculation
#' @return Coefficient of variation
#' @examples
#' cv(runif(100))
#'
#' @export
cv <- function(x, na.rm = TRUE) {
  m <- mean(x, na.rm = na.rm)
  if (m == 0) {
    message("Mean should be greater than 0")
    NA
  } else {
    sd(x, na.rm = na.rm) / m
  }
}

#' Standard error
#' @param x Input variable
#' @param na.rm If TRUE missing values are removed before calculation
#' @return Standard error
#' @examples
#' se(rnorm(100))
#'
#' @export
se <- function(x, na.rm = TRUE) {
  if (na.rm) x <- na.omit(x)
  sd(x) / sqrt(length(x))
}

#' Margin of error
#' @param x Input variable
#' @param conf_lev Confidence level. The default is 0.95
#' @param na.rm If TRUE missing values are removed before calculation
#' @return Margin of error
#'
#' @importFrom stats qt
#'
#' @examples
#' me(rnorm(100))
#'
#' @export
me <- function(x, conf_lev = 0.95, na.rm = TRUE) {
  if (na.rm) x <- na.omit(x)
  se(x) * qt(conf_lev / 2 + .5, length(x) - 1, lower.tail = TRUE)
}

#' Calculate proportion
#' @param x Input variable
#' @param na.rm If TRUE missing values are removed before calculation
#' @return Proportion of first level for a factor and of the maximum value for numeric
#' @examples
#' prop(c(rep(1L, 10), rep(0L, 10)))
#' prop(c(rep(4, 10), rep(2, 10)))
#' prop(rep(0, 10))
#' prop(factor(c(rep("a", 20), rep("b", 10))))
#'
#' @export
prop <- function(x, na.rm = TRUE) {
  if (na.rm) x <- na.omit(x)
  if (is.numeric(x)) {
    mean(x == max(x, 1)) ## gives proportion of max value in x
  } else if (is.factor(x)) {
    mean(x == levels(x)[1]) ## gives proportion of first level in x
  } else if (is.logical(x)) {
    mean(x)
  } else {
    NA
  }
}

#' Variance for proportion
#' @param x Input variable
#' @param na.rm If TRUE missing values are removed before calculation
#' @return Variance for proportion
#' @examples
#' varprop(c(rep(1L, 10), rep(0L, 10)))
#'
#' @export
varprop <- function(x, na.rm = TRUE) {
  p <- prop(x, na.rm = na.rm)
  p * (1 - p)
}

#' Standard deviation for proportion
#' @param x Input variable
#' @param na.rm If TRUE missing values are removed before calculation
#' @return Standard deviation for proportion
#' @examples
#' sdprop(c(rep(1L, 10), rep(0L, 10)))
#'
#' @export
sdprop <- function(x, na.rm = TRUE) sqrt(varprop(x, na.rm = na.rm))

#' Standard error for proportion
#' @param x Input variable
#' @param na.rm If TRUE missing values are removed before calculation
#' @return Standard error for proportion
#' @examples
#' seprop(c(rep(1L, 10), rep(0L, 10)))
#'
#' @export
seprop <- function(x, na.rm = TRUE) {
  if (na.rm) x <- na.omit(x)
  sqrt(varprop(x, na.rm = FALSE) / length(x))
}

#' Margin of error for proportion
#' @param x Input variable
#' @param conf_lev Confidence level. The default is 0.95
#' @param na.rm If TRUE missing values are removed before calculation
#' @return Margin of error
#'
#' @importFrom stats qnorm
#'
#' @examples
#' meprop(c(rep(1L, 10), rep(0L, 10)))
#'
#' @export
meprop <- function(x, conf_lev = 0.95, na.rm = TRUE) {
  if (na.rm) x <- na.omit(x)
  seprop(x) * qnorm(conf_lev / 2 + .5, lower.tail = TRUE)
}

#' Variance for the population
#' @param x Input variable
#' @param na.rm If TRUE missing values are removed before calculation
#' @return Variance for the population
#' @examples
#' varpop(rnorm(100))
#'
#' @export
varpop <- function(x, na.rm = TRUE) {
  if (na.rm) x <- na.omit(x)
  n <- length(x)
  var(x) * ((n - 1) / n)
}

#' Standard deviation for the population
#' @param x Input variable
#' @param na.rm If TRUE missing values are removed before calculation
#' @return Standard deviation for the population
#' @examples
#' sdpop(rnorm(100))
#'
#' @export
sdpop <- function(x, na.rm = TRUE) sqrt(varpop(x, na.rm = na.rm))

#' Natural log
#' @param x Input variable
#' @param na.rm Remove missing values (default is TRUE)
#' @return Natural log of vector
#' @examples
#' ln(runif(10, 1, 2))
#'
#' @export
ln <- function(x, na.rm = TRUE) {
  if (na.rm) log(na.omit(x)) else log(x)
}

#' Does a vector have non-zero variability?
#' @param x Input variable
#' @param na.rm If TRUE missing values are removed before calculation
#' @return Logical. TRUE is there is variability
#' @examples
#' summarise_all(diamonds, does_vary) %>% as.logical()
#'
#' @export
does_vary <- function(x, na.rm = TRUE) {
  ## based on http://stackoverflow.com/questions/4752275/test-for-equality-among-all-elements-of-a-single-vector
  if (length(x) == 1L) {
    FALSE
  } else {
    if (is.factor(x) || is.character(x)) {
      length(unique(x)) > 1
    } else {
      abs(max(x, na.rm = na.rm) - min(x, na.rm = na.rm)) > .Machine$double.eps^0.5
    }
  }
}

#' Convert categorical variables to factors and deal with empty/missing values
#' @param x Categorical variable used in table
#' @return Variable with updated levels
#' @export
empty_level <- function(x) {
  if (!is.factor(x)) x <- as.factor(x)
  levs <- levels(x)
  if ("" %in% levs) {
    levs[levs == ""] <- "NA"
    x <- factor(x, levels = levs)
    x[is.na(x)] <- "NA"
  } else if (any(is.na(x))) {
    x <- factor(x, levels = unique(c(levs, "NA")))
    x[is.na(x)] <- "NA"
  }
  x
}

#' Calculate the mode (modal value) and return a label
#'
#' @details From https://www.tutorialspoint.com/r/r_mean_median_mode.htm
#' @param x A vector
#' @param na.rm If TRUE missing values are removed before calculation
#'
#' @examples
#' modal(c("a", "b", "b"))
#' modal(c(1:10, 5))
#' modal(as.factor(c(letters, "b")))
#' modal(runif(100) > 0.5)
#'
#' @export
modal <- function(x, na.rm = TRUE) {
  if (na.rm) x <- na.omit(x)
  unv <- unique(x)
  unv[which.max(tabulate(match(x, unv)))]
}
