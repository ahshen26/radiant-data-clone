################################################################################
## functions to set initial values and take information from r_state
## when available
################################################################################

## useful options for debugging
# options(shiny.trace = TRUE)
# options(shiny.error = recover)
# options(warn = 2)

if (isTRUE(getOption("radiant.shinyFiles", FALSE))) {
  if (isTRUE(Sys.getenv("RSTUDIO") == "") && isTRUE(Sys.getenv("SHINY_PORT") != "")) {
    ## Users not on Rstudio will only get access to pre-specified volumes
    sf_volumes <- getOption("radiant.sf_volumes", "")
  } else {
    if (getOption("radiant.project_dir", "") == "") {
      sf_volumes <- getOption("radiant.launch_dir") %>%
        {
          set_names(., basename(.))
        }
    } else {
      sf_volumes <- getOption("radiant.project_dir") %>%
        {
          set_names(., basename(.))
        }
    }
    home <- radiant.data::find_home()
    if (home != sf_volumes) {
      sf_volumes <- c(sf_volumes, home) %>% set_names(c(names(sf_volumes), "Home"))
    } else {
      sf_volumes <- c(Home = home)
    }
    if (sum(nzchar(getOption("radiant.sf_volumes", ""))) > 0) {
      sf_volumes <- getOption("radiant.sf_volumes") %>%
        {
          c(sf_volumes, .[!. %in% sf_volumes])
        }
    }
    missing_names <- is.na(names(sf_volumes))
    if (sum(missing_names) > 0) {
      sf_volumes[missing_names] <- basename(sf_volumes[missing_names])
    }
  }
}

remove_session_files <- function(st = Sys.time()) {
  fl <- list.files(
    normalizePath("~/.radiant.sessions/"),
    pattern = "*.state.rda",
    full.names = TRUE
  )

  for (f in fl) {
    if (difftime(st, file.mtime(f), units = "days") > 7) {
      unlink(f, force = TRUE)
    }
  }
}

remove_session_files()

## from Joe Cheng's https://github.com/jcheng5/shiny-resume/blob/master/session.R
isolate({
  prevSSUID <- parseQueryString(session$clientData$url_search)[["SSUID"]]
})

most_recent_session_file <- function() {
  fl <- list.files(
    normalizePath("~/.radiant.sessions/"),
    pattern = "*.state.rda",
    full.names = TRUE
  )

  if (length(fl) > 0) {
    data.frame(fn = fl, dt = file.mtime(fl), stringsAsFactors = FALSE) %>%
      arrange(desc(dt)) %>%
      slice(1) %>%
      .[["fn"]] %>%
      as.character() %>%
      basename() %>%
      gsub("r_(.*).state.rda", "\\1", .)
  } else {
    NULL
  }
}

## set the session id
r_ssuid <- if (getOption("radiant.local")) {
  if (is.null(prevSSUID)) {
    mrsf <- most_recent_session_file()
    paste0("local-", shiny:::createUniqueId(3))
  } else {
    mrsf <- "0000"
    prevSSUID
  }
} else {
  ifelse(is.null(prevSSUID), shiny:::createUniqueId(5), prevSSUID)
}

## (re)start the session and push the id into the url
session$sendCustomMessage("session_start", r_ssuid)

## identify the shiny environment
## deprecated - will be removed in future version
r_environment <- session$token

r_info_legacy <- function() {
  r_info_elements <- c(
    "datasetlist", "dtree_list", "pvt_rows", "nav_radiant",
    "plot_height", "plot_width", "filter_error", "cmb_error"
  ) %>%
    c(paste0(r_data[["datasetlist"]], "_descr"))
  r_info <- reactiveValues()
  for (i in r_info_elements) {
    r_info[[i]] <- r_data[[i]]
  }
  suppressWarnings(rm(list = r_info_elements, envir = r_data))
  r_info
}

## load for previous state if available but look in global memory first
if (isTRUE(getOption("radiant.local")) && exists("r_data", envir = .GlobalEnv)) {
  r_data <- if (is.list(r_data)) list2env(r_data, envir = new.env()) else r_data
  if (exists("r_info")) {
    r_info <- do.call(reactiveValues, r_info)
  } else {
    r_info <- r_info_legacy()
  }
  r_state <- if (exists("r_state")) r_state else list()
  suppressWarnings(rm(r_data, r_state, r_info, envir = .GlobalEnv))
} else if (isTRUE(getOption("radiant.local")) && !is.null(r_sessions[[r_ssuid]]$r_data)) {
  r_data <- r_sessions[[r_ssuid]]$r_data %>%
    {
      if (is.list(.)) list2env(., envir = new.env()) else .
    }
  if (is.null(r_sessions[[r_ssuid]]$r_info)) {
    r_info <- r_info_legacy()
  } else {
    r_info <- do.call(reactiveValues, r_sessions[[r_ssuid]]$r_info)
  }
  r_state <- r_sessions[[r_ssuid]]$r_state
} else if (file.exists(paste0("~/.radiant.sessions/r_", r_ssuid, ".state.rda"))) {
  ## read from file if not in global
  fn <- paste0(normalizePath("~/.radiant.sessions"), "/r_", r_ssuid, ".state.rda")
  rs <- new.env(emptyenv())
  try(load(fn, envir = rs), silent = TRUE)
  if (inherits(rs, "try-error")) {
    r_data <- new.env()
    r_info <- init_data(env = r_data)
    r_state <- list()
  } else {
    if (length(rs$r_data) == 0) {
      r_data <- new.env()
      r_info <- init_data(env = r_data)
    } else {
      r_data <- rs$r_data %>%
        {
          if (is.list(.)) list2env(., envir = new.env()) else .
        }
      if (is.null(rs$r_info)) {
        r_info <- r_info_legacy()
      } else {
        r_info <- do.call(reactiveValues, rs$r_info)
      }
    }
    if (length(rs$r_state) == 0) {
      r_state <- list()
    } else {
      r_state <- rs$r_state
    }
  }

  unlink(fn, force = TRUE)
  rm(rs)
} else if (isTRUE(getOption("radiant.local")) && file.exists(paste0("~/.radiant.sessions/r_", mrsf, ".state.rda"))) {
  ## restore from local folder but assign new ssuid
  fn <- paste0(normalizePath("~/.radiant.sessions"), "/r_", mrsf, ".state.rda")
  rs <- new.env(emptyenv())
  try(load(fn, envir = rs), silent = TRUE)
  if (inherits(rs, "try-error")) {
    r_data <- new.env()
    r_info <- init_data(env = r_data)
    r_state <- list()
  } else {
    if (length(rs$r_data) == 0) {
      r_data <- new.env()
      r_info <- init_data(env = r_data)
    } else {
      r_data <- rs$r_data %>%
        {
          if (is.list(.)) list2env(., envir = new.env()) else .
        }
      r_info <- if (length(rs$r_info) == 0) {
        r_info <- r_info_legacy()
      } else {
        do.call(reactiveValues, rs$r_info)
      }
    }
    r_state <- if (length(rs$r_state) == 0) list() else rs$r_state
  }

  ## don't navigate to same tab in case the app locks again
  r_state$nav_radiant <- NULL
  unlink(fn, force = TRUE)
  rm(rs)
} else {
  r_data <- new.env()
  r_info <- init_data(env = r_data)
  r_state <- list()
}

isolate({
  for (ds in r_info[["datasetlist"]]) {
    if (exists(ds, envir = r_data) && !bindingIsActive(as.symbol(ds), env = r_data)) {
      shiny::makeReactiveBinding(ds, env = r_data)
    }
  }
  for (dt in r_info[["dtree_list"]]) {
    if (exists(dt, envir = r_data)) {
      r_data[[dt]] <- add_class(r_data[[dt]], "dtree")
      if (!bindingIsActive(as.symbol(dt), env = r_data)) {
        shiny::makeReactiveBinding(dt, env = r_data)
      }
    }
  }
})

## legacy, to deal with state files created before
## Report > Rmd and Report > R name change
if (isTRUE(r_state$nav_radiant == "Code")) {
  r_state$nav_radiant <- "R"
} else if (isTRUE(r_state$nav_radiant == "Report")) {
  r_state$nav_radiant <- "Rmd"
}

## legacy, to deal with radio buttons that were in Data > Pivot
if (!is.null(r_state$pvt_type)) {
  if (isTRUE(r_state$pvt_type == "fill")) {
    r_state$pvt_type <- TRUE
  } else {
    r_state$pvt_type <- FALSE
  }
}

## legacy, to deal with state files created before
## name change to rmd_edit
if (!is.null(r_state$rmd_report) && is.null(r_state$rmd_edit)) {
  r_state$rmd_edit <- r_state$rmd_report
  r_state$rmd_report <- NULL
}

if (length(r_state$rmd_edit) > 0) {
  r_state$rmd_edit <- r_state$rmd_edit %>% radiant.data::fix_smart()
}

## legacy, to deal with state files created before
## name change to rmd_edit
if (!is.null(r_state$rcode_edit) && is.null(r_state$r_edit)) {
  r_state$r_edit <- r_state$rcode_edit
  r_state$rcode_edit <- NULL
}

## parse the url and use updateTabsetPanel to navigate to the desired tab
## currently only works with a new or refreshed session
observeEvent(session$clientData$url_search, {
  url_query <- parseQueryString(session$clientData$url_search)
  if ("url" %in% names(url_query)) {
    r_info[["url"]] <- url_query$url
  } else if (is.empty(r_info[["url"]])) {
    return()
  }

  ## create an observer and suspend when done
  url_observe <- observe({
    if (is.null(input$dataset)) {
      return()
    }
    url <- getOption("radiant.url.patterns")[[r_info[["url"]]]]
    if (is.null(url)) {
      ## if pattern not found suspend observer
      url_observe$suspend()
      return()
    }
    ## move through the url
    for (u in names(url)) {
      if (is.null(input[[u]])) {
        return()
      }
      if (input[[u]] != url[[u]]) {
        updateTabsetPanel(session, u, selected = url[[u]])
      }
      if (names(tail(url, 1)) == u) url_observe$suspend()
    }
  })
})

## keeping track of the main tab we are on
observeEvent(input$nav_radiant, {
  if (!input$nav_radiant %in% c("Refresh", "Stop")) {
    r_info[["nav_radiant"]] <- input$nav_radiant
  }
})

## Jump to the page you were on
## only goes two layers deep at this point
if (!is.null(r_state$nav_radiant)) {
  ## don't return-to-the-spot if that was quit or stop
  if (r_state$nav_radiant %in% c("Refresh", "Stop")) {
    return()
  }

  ## naming the observer so we can suspend it when done
  nav_observe <- observe({
    ## needed to avoid errors when no data is available yet
    if (is.null(input$dataset)) {
      return()
    }
    updateTabsetPanel(session, "nav_radiant", selected = r_state$nav_radiant)

    ## check if shiny set the main tab to the desired value
    if (is.null(input$nav_radiant)) {
      return()
    }
    if (input$nav_radiant != r_state$nav_radiant) {
      return()
    }
    nav_radiant_tab <- getOption("radiant.url.list")[[r_state$nav_radiant]] %>%
      names()

    if (!is.null(nav_radiant_tab) && !is.null(r_state[[nav_radiant_tab]])) {
      updateTabsetPanel(session, nav_radiant_tab, selected = r_state[[nav_radiant_tab]])
    }

    ## once you arrive at the desired tab suspend the observer
    nav_observe$suspend()
  })
}

isolate({
  if (is.null(r_info[["plot_height"]])) r_info[["plot_height"]] <- 650
  if (is.null(r_info[["plot_width"]])) r_info[["plot_width"]] <- 650
})

if (getOption("radiant.from.package", default = TRUE)) {
  ## launch using installed radiant.data package
  # radiant.data::copy_all("radiant.data")
  cat("\nGetting radiant.data from package ...\n")
} else {
  ## for shiny-server and development
  for (file in list.files("../../R", pattern = "\\.(r|R)$", full.names = TRUE)) {
    source(file, encoding = getOption("radiant.encoding", "UTF-8"), local = TRUE)
  }
  cat("\nGetting radiant.data from source ...\n")
}

## Getting screen width ...
## https://github.com/rstudio/rstudio/issues/1870
## https://community.rstudio.com/t/rstudio-resets-width-option-when-running-shiny-app-in-viewer/3661
observeEvent(input$get_screen_width, {
  if (getOption("width", default = 250) != 250) options(width = 250)
})


radiant.data::copy_from(radiant.data, register, deregister)
