################################################################################
## function to save app state on refresh or crash
################################################################################

## drop NULLs in list
toList <- function(x) reactiveValuesToList(x) %>% .[!sapply(., is.null)]

## from https://gist.github.com/hadley/5434786
env2list <- function(x) mget(ls(x), x)

is_active <- function(env = r_data) {
  sapply(ls(envir = env), function(x) bindingIsActive(as.symbol(x), env = env))
}

## remove non-active bindings
rem_non_active <- function(env = r_data) {
  iact <- is_active(env = r_data)
  rm(list = names(iact)[!iact], envir = env)
}

active2list <- function(env = r_data) {
  iact <- is_active(env = r_data) %>% (function(x) names(x)[x])
  if (length(iact) > 0) {
    mget(iact, env)
  } else {
    list()
  }
}

## deal with https://github.com/rstudio/shiny/issues/2065
MRB <- function(x, env = parent.frame(), init = FALSE) {
  if (exists(x, envir = env)) {
    ## if the object exists and has a binding, don't do anything
    if (!bindingIsActive(as.symbol(x), env = env)) {
      shiny::makeReactiveBinding(x, env = env)
    }
  } else if (init) {
    ## initialize a binding (and value) if object doesn't exist yet
    shiny::makeReactiveBinding(x, env = env)
  }
}

saveSession <- function(session = session, timestamp = FALSE, path = "~/.radiant.sessions") {
  if (!exists("r_sessions")) {
    return()
  }
  if (!dir.exists(path)) dir.create(path)
  isolate({
    LiveInputs <- toList(input)
    r_state[names(LiveInputs)] <- LiveInputs

    ## removing the non-active bindings
    rem_non_active()

    r_data <- env2list(r_data)
    r_info <- toList(r_info)

    r_sessions[[r_ssuid]] <- list(
      r_data = r_data,
      r_info = r_info,
      r_state = r_state,
      timestamp = Sys.time()
    )

    ## saving session information to state file
    if (timestamp) {
      fn <- paste0(normalizePath(path), "/r_", r_ssuid, "-", gsub("( |:)", "-", Sys.time()), ".state.rda")
    } else {
      fn <- paste0(normalizePath(path), "/r_", r_ssuid, ".state.rda")
    }
    save(r_data, r_info, r_state, file = fn)
  })
}

observeEvent(input$refresh_radiant, {
  if (isTRUE(getOption("radiant.local"))) {
    fn <- normalizePath("~/.radiant.sessions")
    file.remove(list.files(fn, full.names = TRUE))
  } else {
    fn <- paste0(normalizePath("~/.radiant.sessions"), "/r_", r_ssuid, ".state.rda")
    if (file.exists(fn)) unlink(fn, force = TRUE)
  }

  try(r_ssuid <- NULL, silent = TRUE)
})

saveStateOnRefresh <- function(session = session) {
  session$onSessionEnded(function() {
    isolate({
      url_query <- parseQueryString(session$clientData$url_search)
      if (not_pressed(input$refresh_radiant) &&
        not_pressed(input$stop_radiant) &&
        not_pressed(input$state_load) &&
        not_pressed(input$state_upload) &&
        !"fixed" %in% names(url_query)) {
        saveSession(session)
      } else {
        if (not_pressed(input$state_load) && not_pressed(input$state_upload)) {
          if (exists("r_sessions")) {
            sshhr(try(r_sessions[[r_ssuid]] <- NULL, silent = TRUE))
            sshhr(try(rm(r_ssuid), silent = TRUE))
          }
        }
      }
    })
  })
}

################################################################
## functions used across tools in radiant
################################################################

## get active dataset and apply data-filter if available
.get_data <- reactive({
  req(input$dataset)

  filter_cmd <- input$data_filter %>%
    gsub("\\n", "", .) %>%
    gsub("\"", "\'", .) %>%
    fix_smart()

  arrange_cmd <- input$data_arrange
  if (!is.empty(arrange_cmd)) {
    arrange_cmd <- arrange_cmd %>%
      strsplit(., split = "(&|,|\\s+)") %>%
      unlist() %>%
      .[!. == ""] %>%
      paste0(collapse = ", ") %>%
      (function(x) glue("arrange(x, {x})"))
  }

  slice_cmd <- input$data_rows

  if ((is.empty(filter_cmd) && is.empty(arrange_cmd) && is.empty(slice_cmd)) || input$show_filter == FALSE) {
    isolate(r_info[["filter_error"]] <- "")
  } else if (grepl("([^=!<>])=([^=])", filter_cmd)) {
    isolate(r_info[["filter_error"]] <- "Invalid filter: Never use = in a filter! Use == instead (e.g., city == 'San Diego'). Update or remove the expression")
  } else {
    ## %>% needed here so . will be available
    seldat <- try(
      r_data[[input$dataset]] %>%
        (function(x) if (!is.empty(filter_cmd)) x %>% filter(!!rlang::parse_expr(filter_cmd)) else x) %>%
        (function(x) if (!is.empty(arrange_cmd)) eval(parse(text = arrange_cmd)) else x) %>%
        (function(x) if (!is.empty(slice_cmd)) x %>% slice(!!rlang::parse_expr(slice_cmd)) else x),
      silent = TRUE
    )
    if (inherits(seldat, "try-error")) {
      isolate(r_info[["filter_error"]] <- paste0("Invalid input: \"", attr(seldat, "condition")$message, "\". Update or remove the expression(x)"))
    } else {
      isolate(r_info[["filter_error"]] <- "")
      if ("grouped_df" %in% class(seldat)) {
        return(droplevels(ungroup(seldat)))
      } else {
        return(droplevels(seldat))
      }
    }
  }
  if ("grouped_df" %in% class(r_data[[input$dataset]])) {
    ungroup(r_data[[input$dataset]])
  } else {
    r_data[[input$dataset]]
  }
})

## using a regular function to avoid a full data copy
.get_data_transform <- function(dataset = input$dataset) {
  if (is.null(dataset)) {
    return()
  }
  if ("grouped_df" %in% class(r_data[[dataset]])) {
    ungroup(r_data[[dataset]])
  } else {
    r_data[[dataset]]
  }
}

.get_class <- reactive({
  get_class(.get_data())
})

groupable_vars <- reactive({
  .get_data() %>%
    summarise_all(
      list(
        ~ is.factor(.) || is.logical(.) || lubridate::is.Date(.) ||
          is.integer(.) || is.character(.) ||
          ((length(unique(.)) / n()) < 0.30)
      )
    ) %>%
    (function(x) which(x == TRUE)) %>%
    varnames()[.]
})

groupable_vars_nonum <- reactive({
  .get_data() %>%
    summarise_all(
      list(
        ~ is.factor(.) || is.logical(.) ||
          lubridate::is.Date(.) || is.integer(.) ||
          is.character(.)
      )
    ) %>%
    (function(x) which(x == TRUE)) %>%
    varnames()[.]
})

## used in compare proportions, logistic, etc.
two_level_vars <- reactive({
  two_levs <- function(x) {
    if (is.factor(x)) {
      length(levels(x))
    } else {
      length(unique(na.omit(x)))
    }
  }
  .get_data() %>%
    summarise_all(two_levs) %>%
    (function(x) x == 2) %>%
    which(.) %>%
    varnames()[.]
})

## used in visualize - don't plot Y-variables that don't vary
varying_vars <- reactive({
  .get_data() %>%
    summarise_all(does_vary) %>%
    as.logical() %>%
    which() %>%
    varnames()[.]
})

## getting variable names in active dataset and their class
varnames <- reactive({
  var_class <- .get_class()
  req(var_class)
  names(var_class) %>%
    set_names(., paste0(., " {", var_class, "}"))
})

## cleaning up the arguments for data_filter and defaults passed to report
clean_args <- function(rep_args, rep_default = list()) {
  if (!is.null(rep_args$data_filter)) {
    if (rep_args$data_filter == "") {
      rep_args$data_filter <- NULL
    } else {
      rep_args$data_filter %<>% gsub("\\n", "", .) %>% gsub("\"", "\'", .)
    }
  }
  if (is.empty(rep_args$rows)) {
    rep_args$rows <- NULL
  }
  if (is.empty(rep_args$arr)) {
    rep_args$arr <- NULL
  }

  if (length(rep_default) == 0) rep_default[names(rep_args)] <- ""

  ## removing default arguments before sending to report feature
  for (i in names(rep_args)) {
    if (!is.language(rep_args[[i]]) && !is.call(rep_args[[i]]) && all(is.na(rep_args[[i]]))) {
      rep_args[[i]] <- NULL
      next
    }
    if (!is.symbol(rep_default[[i]]) && !is.call(rep_default[[i]]) && all(is_not(rep_default[[i]]))) next
    if (length(rep_args[[i]]) == length(rep_default[[i]]) && !is.name(rep_default[[i]]) && all(rep_args[[i]] == rep_default[[i]])) {
      rep_args[[i]] <- NULL
    }
  }

  rep_args
}

## check if a variable is null or not in the selected data.frame
not_available <- function(x) any(is.null(x)) || (sum(x %in% varnames()) < length(x))

## check if a variable is null or not in the selected data.frame
available <- function(x) !not_available(x)

## check if a button was pressed
pressed <- function(x) !is.null(x) && (is.list(x) || x > 0)

## check if a button was NOT pressed
not_pressed <- function(x) !pressed(x)

## check for duplicate entries
has_duplicates <- function(x) length(unique(x)) < length(x)

## is x some type of date variable
is_date <- function(x) inherits(x, c("Date", "POSIXlt", "POSIXct"))

## drop elements from .._args variables obtained using formals
r_drop <- function(x, drop = c("dataset", "data_filter", "arr", "rows", "envir")) x[!x %in% drop]

## show a few rows of a dataframe
show_data_snippet <- function(dataset = input$dataset, nshow = 7, title = "", filt = "", arr = "", rows = "") {
  if (is.character(dataset) && length(dataset) == 1) dataset <- get_data(dataset, filt = filt, arr = arr, rows = rows, na.rm = FALSE, envir = r_data)
  nr <- nrow(dataset)
  ## avoid slice with variables outside of the df in case a column with the same
  ## name exists
  dataset[1:min(nshow, nr), , drop = FALSE] %>%
    mutate_if(is_date, as.character) %>%
    mutate_if(is.character, list(~ strtrim(., 40))) %>%
    xtable::xtable(.) %>%
    print(
      type = "html", print.results = FALSE, include.rownames = FALSE,
      sanitize.text.function = identity,
      html.table.attributes = "class='table table-condensed table-hover snippet'"
    ) %>%
    paste0(title, .) %>%
    (function(x) if (nr <= nshow) x else paste0(x, "\n<label>", nshow, " of ", format_nr(nr, dec = 0), " rows shown. See View-tab for details.</label>")) %>%
    enc2utf8()
}

suggest_data <- function(text = "", df_name = "diamonds") {
  paste0(text, "For an example dataset go to Data > Manage, select 'examples' from the\n'Load data of type' dropdown, and press the 'Load examples' button. Then\nselect the \'", df_name, "\' dataset.")
}

## function written by @wch https://github.com/rstudio/shiny/issues/781#issuecomment-87135411
capture_plot <- function(expr, env = parent.frame()) {
  structure(
    list(expr = substitute(expr), env = env),
    class = "capture_plot"
  )
}

## function written by @wch https://github.com/rstudio/shiny/issues/781#issuecomment-87135411
print.capture_plot <- function(x, ...) {
  eval(x$expr, x$env)
}

################################################################
## functions used to create Shiny in and outputs
################################################################

## textarea where the return key submits the content
returnTextAreaInput <- function(inputId, label = NULL, rows = 2,
                                placeholder = NULL, resize = "vertical",
                                value = "") {
  ## avoid all sorts of 'helpful' behavior from your browser
  ## see https://stackoverflow.com/a/35514029/1974918
  tagList(
    tags$div(
      # using containing element based on
      # https://github.com/niklasvh/html2canvas/issues/2008#issuecomment-1445503369
      tags$label(label, `for` = inputId), br(),
      tags$textarea(
        value,
        id = inputId,
        type = "text",
        rows = rows,
        placeholder = placeholder,
        resize = resize,
        autocomplete = "off",
        autocorrect = "off",
        autocapitalize = "off",
        spellcheck = "false",
        class = "returnTextArea form-control"
      )
    )
  )
}

## from https://github.com/rstudio/shiny/blob/master/R/utils.R
`%AND%` <- function(x, y) {
  if (!all(is.null(x)) && !all(is.na(x))) {
    if (!all(is.null(y)) && !all(is.na(y))) {
      return(y)
    }
  }
  return(NULL)
}

## using a custom version of textInput to avoid browser "smartness"
textInput <- function(inputId, label, value = "", width = NULL,
                      placeholder = NULL, autocomplete = "off",
                      autocorrect = "off", autocapitalize = "off",
                      spellcheck = "false", ...) {
  value <- restoreInput(id = inputId, default = value)
  div(
    class = "form-group shiny-input-container",
    style = if (!is.null(width)) paste0("width: ", validateCssUnit(width), ";"),
    label %AND% tags$label(label, `for` = inputId),
    tags$input(
      id = inputId,
      type = "text",
      class = "form-control",
      value = value,
      placeholder = placeholder,
      autocomplete = autocomplete,
      autocorrect = autocorrect,
      autocapitalize = autocapitalize,
      spellcheck = spellcheck,
      ...
    )
  )
}

## using a custom version of textAreaInput to avoid browser "smartness"
textAreaInput <- function(inputId, label, value = "", width = NULL,
                          height = NULL, cols = NULL, rows = NULL,
                          placeholder = NULL, resize = NULL,
                          autocomplete = "off", autocorrect = "off",
                          autocapitalize = "off", spellcheck = "true",
                          ...) {
  value <- restoreInput(id = inputId, default = value)
  if (!is.null(resize)) {
    resize <- match.arg(
      resize,
      c("both", "none", "vertical", "horizontal")
    )
  }
  style <- paste(if (!is.null(width)) {
    paste0("width: ", validateCssUnit(width), ";")
  }, if (!is.null(height)) {
    paste0("height: ", validateCssUnit(height), ";")
  }, if (!is.null(resize)) {
    paste0("resize: ", resize, ";")
  })
  if (length(style) == 0) {
    style <- NULL
  }
  div(
    class = "form-group shiny-input-container",
    label %AND% tags$label(label, `for` = inputId),
    tags$textarea(
      id = inputId,
      class = "form-control",
      placeholder = placeholder,
      style = style,
      rows = rows,
      cols = cols,
      autocomplete = autocomplete,
      autocorrect = autocorrect,
      autocapitalize = autocapitalize,
      spellcheck = spellcheck,
      ...,
      value
    )
  )
}

## avoid all sorts of 'helpful' behavior from your browser
## based on https://stackoverflow.com/a/35514029/1974918
returnTextInput <- function(inputId, label = NULL,
                            placeholder = NULL, value = "") {
  tagList(
    tags$label(label, `for` = inputId),
    tags$input(
      id = inputId,
      type = "text",
      value = value,
      placeholder = placeholder,
      autocomplete = "off",
      autocorrect = "off",
      autocapitalize = "off",
      spellcheck = "false",
      class = "returnTextInput form-control"
    )
  )
}

if (getOption("radiant.shinyFiles", FALSE)) {
  download_link <- function(id) {
    uiOutput(paste0("ui_", id))
  }

  download_button <- function(id, ...) {
    uiOutput(paste0("ui_", id))
  }

  download_handler <- function(id, label = "", fun = id, fn, type = "csv", caption = "Save to csv",
                               class = "", ic = "download", btn = "link", onclick = "function() none;", ...) {
    ## create observer
    shinyFiles::shinyFileSave(input, id, roots = sf_volumes, session = session)

    ## create renderUI
    if (btn == "link") {
      output[[paste0("ui_", id)]] <- renderUI({
        if (is.function(fn)) fn <- fn()
        if (is.function(type)) type <- type()
        shinyFiles::shinySaveLink(
          id, label, caption,
          filename = fn, filetype = type,
          class = "alignright", icon = icon(ic, verify_fa = FALSE), onclick = onclick
        )
      })
    } else {
      output[[paste0("ui_", id)]] <- renderUI({
        if (is.function(fn)) fn <- fn()
        if (is.function(type)) type <- type()
        shinyFiles::shinySaveButton(
          id, label, caption,
          filename = fn, filetype = type,
          class = class, icon = icon("download", verify_fa = FALSE), onclick = onclick
        )
      })
    }

    observeEvent(input[[id]], {
      if (is.integer(input[[id]])) {
        return()
      }
      path <- shinyFiles::parseSavePath(sf_volumes, input[[id]])
      if (!inherits(path, "try-error") && !is.empty(path$datapath)) {
        fun(path$datapath, ...)
      }
    })
  }
} else {
  download_link <- function(id, ...) {
    downloadLink(id, "", class = "fa fa-download alignright", ...)
  }
  download_button <- function(id, label = "Save", ic = "download", class = "", ...) {
    downloadButton(id, label, class = class, ...)
  }
  download_handler <- function(id, label = "", fun = id, fn, type = "csv", caption = "Save to csv",
                               class = "", ic = "download", btn = "link", ...) {
    output[[id]] <- downloadHandler(
      filename = function() {
        if (is.function(fn)) fn <- fn()
        if (is.function(type)) type <- type()
        paste0(fn, ".", type)
      },
      content = function(path) {
        fun(path, ...)
      }
    )
  }
}

plot_width <- function() {
  if (is.null(input$viz_plot_width)) r_info[["plot_width"]] else input$viz_plot_width
}

plot_height <- function() {
  if (is.null(input$viz_plot_height)) r_info[["plot_height"]] else input$viz_plot_height
}

download_handler_plot <- function(path, plot, width = plot_width, height = plot_height) {
  plot <- try(plot(), silent = TRUE)
  if (inherits(plot, "try-error") || is.character(plot) || is.null(plot)) {
    plot <- ggplot() +
      labs(title = "Plot not available")
    inp <- c(500, 100, 96)
  } else {
    inp <- 5 * c(width(), height(), 96)
  }

  png(file = path, width = inp[1], height = inp[2], res = inp[3])
  print(plot)
  dev.off()
}

## fun_name is a string of the main function name
## rfun_name is a string of the reactive wrapper that calls the main function
## out_name is the name of the output, set to fun_name by default
register_print_output <- function(fun_name, rfun_name, out_name = fun_name) {
  ## Generate output for the summary tab
  output[[out_name]] <- renderPrint({
    ## when no analysis was conducted (e.g., no variables selected)
    fun <- get(rfun_name)()
    if (is.character(fun)) {
      cat(fun, "\n")
    } else {
      rm(fun)
    }
  })
  return(invisible())
}

## fun_name is a string of the main function name
## rfun_name is a string of the reactive wrapper that calls the main function
## out_name is the name of the output, set to fun_name by default
register_plot_output <- function(fun_name, rfun_name, out_name = fun_name,
                                 width_fun = "plot_width", height_fun = "plot_height") {
  ## Generate output for the plots tab
  output[[out_name]] <- renderPlot(
    {
      ## when no analysis was conducted (e.g., no variables selected)
      p <- get(rfun_name)()
      if (is_not(p) || is.empty(p)) p <- "Nothing to plot ...\nSelect plots to show or re-run the calculations"
      if (is.character(p)) {
        plot(
          x = 1, type = "n", main = paste0("\n\n\n\n\n\n\n\n", p),
          axes = FALSE, xlab = "", ylab = "", cex.main = .9
        )
      } else {
        print(p)
      }
    },
    width = get(width_fun),
    height = get(height_fun),
    res = 96
  )

  return(invisible())
}

stat_tab_panel <- function(menu, tool, tool_ui, output_panels,
                           data = input$dataset) {
  sidebarLayout(
    sidebarPanel(
      wellPanel(
        HTML(paste("<label><strong>Menu:", menu, "</strong></label><br>")),
        HTML(paste("<label><strong>Tool:", tool, "</strong></label><br>")),
        if (!is.null(data)) {
          HTML(paste("<label><strong>Data:", data, "</strong></label>"))
        }
      ),
      uiOutput(tool_ui)
    ),
    mainPanel(
      output_panels
    )
  )
}

################################################################
## functions used for app help
################################################################
help_modal <- function(modal_title, link, help_file,
                       author = "Vincent Nijs",
                       year = lubridate::year(lubridate::now()),
                       lic = "by-nc-sa") {
  sprintf(
    "<div class='modal fade' id='%s' tabindex='-1' role='dialog' aria-labelledby='%s_label' aria-hidden='true'>
       <div class='help-modal-dialog modal-dialog modal-lg'>
         <div class='modal-content'>
           <div class='modal-header'>
             <h4 class='modal-title' id='%s_label'>%s</h4>
             <button type='button' class='close' data-dismiss='modal' aria-label='Close'><span aria-hidden='true'>&times;</span></button>
           </div>
           <div class='help-modal-body modal-body'>%s<br>
             &copy; %s (%s) <a rel='license' href='http://creativecommons.org/licenses/%s/4.0/' target='_blank'><img alt='Creative Commons License' style='border-width:0' src ='imgs/%s.png' /></a>
           </div>
         </div>
       </div>
     </div>
     <i title='Help' class='fa fa-question' data-toggle='modal' data-target='#%s'></i>",
    link, link, link, modal_title, help_file, author, year, lic, lic, link
  ) %>%
    enc2utf8() %>%
    HTML()
}

help_and_report <- function(modal_title, fun_name, help_file,
                            author = "Vincent Nijs",
                            year = lubridate::year(lubridate::now()),
                            lic = "by-nc-sa") {
  sprintf(
    "<div class='modal fade' id='%s_help' tabindex='-1' role='dialog' aria-labelledby='%s_help_label' aria-hidden='true'>
       <div class='help-modal-dialog modal-dialog modal-lg'>
         <div class='modal-content'>
           <div class='modal-header'>
             <h4 class='modal-title' id='%s_help_label'>%s</h4>
             <button type='button' class='close' data-dismiss='modal' aria-label='Close'><span aria-hidden='true'>&times;</span></button>
           </div>
           <div class='help-modal-body modal-body'>%s<br>
             &copy; %s (%s) <a rel='license' href='http://creativecommons.org/licenses/%s/4.0/' target='_blank'><img alt='Creative Commons License' style='border-width:0' src ='imgs/%s.png' /></a>
           </div>
         </div>
       </div>
     </div>
     <i title='Help' class='fa fa-question alignleft' data-toggle='modal' data-target='#%s_help'></i>
     <i title='Report results & Screenshot' class='fa fa-camera action-button aligncenter' href='#%s_screenshot' id='%s_screenshot' onclick='generate_screenshot();'></i>
     <i title='Report results' class='fa fa-edit action-button alignright' href='#%s_report' id='%s_report'></i>
     <div style='clear: both;'></div>",
    fun_name, fun_name, fun_name, modal_title, help_file, author, year, lic, lic, fun_name, fun_name, fun_name, fun_name, fun_name
  ) %>%
    enc2utf8() %>%
    HTML() %>%
    withMathJax()
}

## function to render .md files to html
inclMD <- function(path) {
  paste(readLines(path, warn = FALSE), collapse = "\n") %>%
    markdown::mark_html(text = ., template = FALSE, meta = list(css = ""), output = FALSE)
}

## function to render .Rmd files to html
inclRmd <- function(path) {
  paste(readLines(path, warn = FALSE), collapse = "\n") %>%
    knitr::knit2html(
      text = ., template = FALSE, quiet = TRUE,
      envir = r_data, meta = list(css = ""), output = FALSE
    ) %>%
    HTML() %>%
    withMathJax()
}

## capture the state of a dt table
dt_state <- function(fun, vars = "", tabfilt = "", tabsort = "", nr = 0) {
  ## global search
  search <- input[[paste0(fun, "_state")]]$search$search
  if (is.null(search)) search <- ""

  ## table ordering
  order <- input[[paste0(fun, "_state")]]$order
  if (length(order) == 0) {
    order <- "NULL"
  } else {
    order <- list(order)
  }

  ## column filters, gsub needed for factors
  sc <- input[[paste0(fun, "_search_columns")]] %>% gsub("\\\"", "'", .)
  sci <- which(sc != "")
  nr_sc <- length(sci)
  if (nr_sc > 0) {
    sc <- list(lapply(sci, function(i) list(i, sc[i])))
  } else if (nr_sc == 0) {
    sc <- "NULL"
  }

  dat <- get(paste0(".", fun))()$tab %>%
    (function(x) {
      nr <<- nrow(x)
      x[1, , drop = FALSE]
    })

  if (order != "NULL" || sc != "NULL") {
    ## get variable class and name
    gc <- get_class(dat) %>%
      (function(x) if (is.empty(vars[1])) x else x[vars])
    cn <- names(gc)

    if (length(cn) > 0) {
      if (order != "NULL") {
        tabsort <- c()
        for (i in order[[1]]) {
          cname <- cn[i[[1]] + 1] %>% gsub("^\\s+|\\s+$", "", .)
          if (grepl("[^0-9a-zA-Z_\\.]", cname) || grepl("^[0-9]", cname)) {
            cname <- paste0("`", cname, "`")
          }
          if (i[[2]] == "desc") cname <- paste0("desc(", cname, ")")
          tabsort <- c(tabsort, cname)
        }
        tabsort <- paste0(tabsort, collapse = ", ")
      }

      if (sc != "NULL") {
        tabfilt <- c()
        for (i in sc[[1]]) {
          cname <- cn[i[[1]]]
          type <- gc[cname]
          if (type == "factor") {
            cname <- paste0(cname, " %in% ", sub("\\[", "c(", i[[2]]) %>% sub("\\]", ")", .))
          } else if (type %in% c("numeric", "integer", "ts")) {
            bnd <- strsplit(i[[2]], "...", fixed = TRUE)[[1]]
            cname <- paste0(cname, " >= ", bnd[1], " & ", cname, " <= ", bnd[2]) %>% gsub("  ", " ", .)
          } else if (type %in% c("date", "period")) {
            bnd <- strsplit(i[[2]], "...", fixed = TRUE)[[1]] %>% gsub(" ", "", .)
            cname <- paste0(cname, " >= '", bnd[1], "' & ", cname, " <= '", bnd[2], "'") %>% gsub("  ", " ", .)
          } else if (type == "character") {
            cname <- paste0("grepl('", i[[2]], "', ", cname, ", ignore.case = TRUE)")
          } else if (type == "logical") {
            cname <- paste0(cname, " == ", toupper(sub("\\['(true|false)'\\]", "\\1", i[[2]])))
          } else {
            message("Variable ", cname, " has type ", type, ". This type is not currently supported to generate code for Report > Rmd or Report > R")
            next
          }
          tabfilt <- c(tabfilt, cname)
        }
        tabfilt <- paste0(tabfilt, collapse = " & ")
      }
    }
  }

  list(search = search, order = order, sc = sc, tabsort = tabsort, tabfilt = tabfilt, nr = nr)
}

## use the value in the input list if available and update r_state
state_init <- function(var, init = "", na.rm = TRUE) {
  isolate({
    ivar <- input[[var]]
    if (var %in% names(input) || length(ivar) > 0) {
      ivar <- input[[var]]
      if ((na.rm && is.empty(ivar)) || length(ivar) == 0) {
        r_state[[var]] <<- NULL
      }
    } else {
      ivar <- .state_init(var, init, na.rm)
    }
    ivar
  })
}

## need a separate function for checkboxGroupInputs
state_group <- function(var, init = "") {
  isolate({
    ivar <- input[[var]]
    if (var %in% names(input) || length(ivar) > 0) {
      ivar <- input[[var]]
      if (is.empty(ivar)) r_state[[var]] <<- NULL
    } else {
      ivar <- .state_init(var, init)
      r_state[[var]] <<- NULL ## line that differs for CBG inputs
    }
    ivar
  })
}

.state_init <- function(var, init = "", na.rm = TRUE) {
  rs <- r_state[[var]]
  if ((na.rm && is.empty(rs)) || length(rs) == 0) init else rs
}

state_single <- function(var, vals, init = character(0)) {
  isolate({
    ivar <- input[[var]]
    if (var %in% names(input) && is.null(ivar)) {
      r_state[[var]] <<- NULL
      ivar
    } else if (available(ivar) && all(ivar %in% vals)) {
      if (length(ivar) > 0) r_state[[var]] <<- ivar
      ivar
    } else if (available(ivar) && any(ivar %in% vals)) {
      ivar[ivar %in% vals]
    } else {
      if (length(ivar) > 0 && all(ivar %in% c("None", "none", ".", ""))) {
        r_state[[var]] <<- ivar
      }
      .state_single(var, vals, init = init)
    }
  })
}

.state_single <- function(var, vals, init = character(0)) {
  rs <- r_state[[var]]
  if (is.empty(rs)) init else vals[vals == rs]
}

state_multiple <- function(var, vals, init = character(0)) {
  isolate({
    ivar <- input[[var]]
    if (var %in% names(input) && is.null(ivar)) {
      r_state[[var]] <<- NULL
      ivar
    } else if (available(ivar) && all(ivar %in% vals)) {
      if (length(ivar) > 0) r_state[[var]] <<- ivar
      ivar
    } else if (available(ivar) && any(ivar %in% vals)) {
      ivar[ivar %in% vals]
    } else {
      if (length(ivar) > 0 && all(ivar %in% c("None", "none", ".", ""))) {
        r_state[[var]] <<- ivar
      }
      .state_multiple(var, vals, init = init)
    }
  })
}

.state_multiple <- function(var, vals, init = character(0)) {
  rs <- r_state[[var]]
  r_state[[var]] <<- NULL

  ## "a" %in% character(0) --> FALSE, letters[FALSE] --> character(0)
  if (is.empty(rs)) vals[vals %in% init] else vals[vals %in% rs]
}

## cat to file
## use with tail -f ~/r_cat.txt in a terminal
# cf <- function(...) {
#   cat(paste0("\n--- called from: ", environmentName(parent.frame()), " (", lubridate::now(), ")\n"), file = "~/r_cat.txt", append = TRUE)
#   out <- paste0(capture.output(...), collapse = "\n")
#   cat("--\n", out, "\n--", sep = "\n", file = "~/r_cat.txt", append = TRUE)
# }

## autosave option
## provide a list with (1) the save interval in minutes, (2) the total duration in minutes, and (3) the path to use
# options(radiant.autosave = list(1, 5, "~/.radiant.sessions"))
# options(radiant.autosave = list(.1, 1, "~/Desktop/radiant.sessions"))
# options(radiant.autosave = list(10, 180, "~/Desktop/radiant.sessions"))
if (length(getOption("radiant.autosave", default = NULL)) > 0) {
  start_time <- Sys.time()
  interval <- getOption("radiant.autosave")[[1]] * 60000
  max_duration <- getOption("radiant.autosave")[[2]]
  autosave_path <- getOption("radiant.autosave")[[3]]
  autosave_path <- ifelse(length(autosave_path) == 0, "~/.radiant.sessions", autosave_path)
  autosave_poll <- reactivePoll(
    interval,
    session,
    checkFunc = function() {
      curr_time <- Sys.time()
      diff_time <- difftime(curr_time, start_time, units = "mins")
      if (diff_time < max_duration) {
        saveSession(session, timestamp = TRUE, autosave_path)
        options(radiant.autosave = list(interval, max_duration - diff_time, autosave_path))
        message("Radiant state was auto-saved at ", curr_time)
      } else {
        if (length(getOption("radiant.autosave", default = NULL)) > 0) {
          showModal(
            modalDialog(
              title = "Radiant state autosave",
              span(glue("The autosave feature has been turned off. Time to save and submit your work by clicking
                on the 'Save' icon in the navigation bar and then on 'Save radiant state file'. To clean the
                state files that were auto-saved, run the following command from the R(studio) console:
                unlink('{autosave_path}/*.state.rda', force = TRUE)")),
              footer = modalButton("OK"),
              size = "m",
              easyClose = TRUE
            )
          )
          options(radiant.autosave = NULL)
        }
      }
    },
    valueFunc = function() {
      return()
    }
  )
}

## update "run" button when relevant inputs are changed
run_refresh <- function(args, pre, init = "evar", tabs = "",
                        label = "Estimate model", relabel = label,
                        inputs = NULL, data = TRUE) {
  observe({
    ## dep on most inputs
    if (data) {
      input$data_filter
      input$data_arrange
      input$data_rows
      input$show_filter
    }
    sapply(r_drop(names(args)), function(x) input[[paste0(pre, "_", x)]])

    ## adding dependence in more inputs
    if (length(inputs) > 0) {
      sapply(inputs, function(x) input[[paste0(pre, "_", x)]])
    }

    run <- isolate(input[[paste0(pre, "_run")]]) %>% pressed()
    check_null <- function(init) {
      all(sapply(init, function(x) is.null(input[[paste0(pre, "_", x)]])))
    }
    if (isTRUE(check_null(init))) {
      if (!is.empty(tabs)) {
        updateTabsetPanel(session, paste0(tabs, " "), selected = "Summary")
      }
      updateActionButton(session, paste0(pre, "_run"), label, icon = icon("play", verify_fa = FALSE))
    } else if (run) {
      updateActionButton(session, paste0(pre, "_run"), relabel, icon = icon("sync", class = "fa-spin", verify_fa = FALSE))
    } else {
      updateActionButton(session, paste0(pre, "_run"), label, icon = icon("play", verify_fa = FALSE))
    }
  })

  observeEvent(input[[paste0(pre, "_run")]], {
    updateActionButton(session, paste0(pre, "_run"), label, icon = icon("play", verify_fa = FALSE))
  })
}

radiant_screenshot_modal <- function(report_on = "") {
  add_button <- function() {
    if (is.empty(report_on)) {
      ""
    } else {
      actionButton(report_on, "Report", icon = icon("edit", verify_fa = FALSE), class = "btn-success")
    }
  }
  showModal(
    modalDialog(
      title = "Radiant screenshot",
      span(shiny::tags$div(id = "screenshot_preview")),
      span(HTML("</br>To include a screenshot in a report first save it to disk by clicking on the <em>Save</em> button. Then click the <em>Report</em> button to insert a reference to the screenshot into <em>Report > Rmd</em>.")),
      footer = tagList(
        tags$table(
          tags$td(download_button("screenshot_save", "Save", ic = "download")),
          tags$td(add_button()),
          tags$td(modalButton("Cancel")),
          align = "right"
        )
      ),
      size = "l",
      easyClose = TRUE
    )
  )
}

observeEvent(input$screenshot_link, {
  radiant_screenshot_modal()
})

render_screenshot <- function() {
  plt <- sub("data:.+base64,", "", input$img_src)
  png::readPNG(base64enc::base64decode(what = plt))
}

download_handler_screenshot <- function(path, plot, ...) {
  plot <- try(plot(), silent = TRUE)
  if (inherits(plot, "try-error") || is.character(plot) || is.null(plot)) {
    plot <- ggplot() +
      labs(title = "Plot not available")
    png(file = path, width = 500, height = 100, res = 96)
    print(plot)
    dev.off()
  } else {
    ppath <- parse_path(path, pdir = getOption("radiant.launch_dir", find_home()), mess = FALSE)
    # r_info[["latest_screenshot"]] <- glue("![]({ppath$rpath})")
    # r_info[["latest_screenshot"]] <- glue("<details>\n<summary>Click to show screenshot</summary>\n<img src='{ppath$rpath}' alt='Radiant screenshot'>\n</details>")
    r_info[["latest_screenshot"]] <- glue("\n<details>\n<summary>Click to show screenshot with Radiant settings to generate output shown below</summary>\n\n![]({ppath$rpath})\n</details></br>\n")
    png::writePNG(plot, path, dpi = 144)
  }
}

observe({
  if (length(input$nav_radiant) > 0) {
    tabset <- names(getOption("radiant.url.list")[[input$nav_radiant]])
    rtn <- if (length(tabset) > 0) {
      paste0(input$nav_radiant, " ", input[[tabset]])
    } else {
      input$nav_radiant
    }
    r_info[["radiant_tab_name"]] <- gsub("[ ]+", "-", rtn) %>%
      gsub("(\\(|\\))", "", .) %>%
      gsub("[-]{2,}", "-", .) %>%
      tolower()
  }
})

download_handler(
  id = "screenshot_save",
  fun = download_handler_screenshot,
  fn = function() paste0(r_info[["radiant_tab_name"]], "-screenshot"),
  type = "png",
  caption = "Save radiant screenshot",
  plot = render_screenshot,
  btn = "button",
  label = "Save",
  class = "btn-primary",
  onclick = "get_img_src();"
)
