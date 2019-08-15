#!/usr/bin/env Rscript
# Execution format for the command line:
# Rscript ParsecLogsAnalysis.R --benchmarkpath=. --analysispath=.
# Tests:
# benchmarkpath <- "D:/@TUM/UCC-2019/code/kubernetes/benchmarks/parsec"
# analysispath <- "D:/@TUM/UCC-2019/code/kubernetes/benchmarks/parsec/tst"

benchmarkpath.prefix <- "--benchmarkpath="
analysispath.prefix <- "--analysispath="

options(warn=-1)

cmd.args <- commandArgs(trailingOnly = FALSE)

benchmarkpath <- cmd.args[which(grepl(benchmarkpath.prefix, cmd.args))]
analysispath <- cmd.args[which(grepl(analysispath.prefix, cmd.args))]

if((length(benchmarkpath) == 0) || (length(analysispath) == 0)) {
  print("Necessary parameters were not specified! Exiting.")
} else {
  
  benchmarkpath <- substring(benchmarkpath,
                             nchar(benchmarkpath.prefix) + 1,
                             nchar(benchmarkpath))
  
  analysispath <- substring(analysispath,
                           nchar(analysispath.prefix) + 1,
                           nchar(analysispath))
  
  get.execution.time.from.string <- function(string) {
    timestr <- strsplit(string, "\t")[[1]][2]
    timestr.splitted <- strsplit(timestr, "m")[[1]]
    mins.num <- as.numeric(timestr.splitted[1])
    secs.num <- as.numeric(substr(timestr.splitted[2], 1, (nchar(timestr.splitted[2]) - 1)))
    secs.total.num <- mins.num * 60 + secs.num
    secs.total.num
  }
  
  # Extracting results of a particular run from the corresponding log file
  get.results.for.single.run <- function(logfilename, testdir) {
    testrunid <- as.numeric(strsplit(logfilename, "[.]")[[1]][1])
    
    log.content <- readLines(paste0(testdir,"/",logfilename))
    
    #benchmark.program <- trimws(strsplit(log.content[grepl("Benchmarks to run:", log.content)], ":")[[1]][2])
    #benchmark.input <- trimws(strsplit(log.content[grepl("Unpacking benchmark input", log.content)], "'")[[1]][2])
    
    #optionsnum <- as.numeric(trimws(strsplit(log.content[grepl("Num of Options", log.content)], ":")[[1]][2]))
    #runsnum <- as.numeric(trimws(strsplit(log.content[grepl("Num of Runs", log.content)], ":")[[1]][2]))
    #datasize <- as.numeric(trimws(strsplit(log.content[grepl("Size of data", log.content)], ":")[[1]][2]))
    
    timereal.str <- log.content[grepl("real\t", log.content)]
    timeuser.str <- log.content[grepl("user\t", log.content)]
    timesys.str <- log.content[grepl("sys\t", log.content)]
    
    timereal <- get.execution.time.from.string(timereal.str)
    timeuser <- get.execution.time.from.string(timeuser.str)
    timesys <- get.execution.time.from.string(timesys.str)
    
    data.frame(suite = "parsec",
               #benchmark.program = benchmark.program,
               #benchmark.input = benchmark.input,
               testrunid = testrunid,
               #optionsnum = optionsnum,
               #runsnum = runsnum,
               #datasize = datasize,
               timereal = timereal,
               timeuser = timeuser,
               timesys = timesys)
  }
  
  # Getting the results for a particulat test (based on single yaml file)
  get.results.for.single.test <- function(testdir, benchmarkpath) {
    require(data.table)
    
    logfilesnames <- list.files(paste0(benchmarkpath, "/results/", testdir))
    test.df <- rbindlist(lapply(logfilesnames, get.results.for.single.run, paste0(benchmarkpath, "/results/", testdir)))
    
    yaml.filename <- paste0(testdir, ".yaml")
    yaml.content <- readLines(paste0(benchmarkpath, "/", yaml.filename))
    
    cpus.lims.reqs <- lapply(strsplit(yaml.content[grepl("cpu:", yaml.content)], ":"), trimws)
    mems.lims.reqs <- lapply(strsplit(yaml.content[grepl("memory:", yaml.content)], ":"), trimws)
    qos.class <- ""
    
    if((length(cpus.lims.reqs) == 0) && (length(mems.lims.reqs) == 0)) {
      qos.class <- "BestEffort"
    } else {
      cpu.guaranteed <- FALSE
      mem.guaranteed <- FALSE
      
      if(length(cpus.lims.reqs) > 0) {
        if((cpus.lims.reqs[[1]][2] == cpus.lims.reqs[[2]][2])) {
          cpu.guaranteed <- TRUE
        }
      }
      
      if(length(mems.lims.reqs) > 0) {
        if((mems.lims.reqs[[1]][2] == mems.lims.reqs[[2]][2])) {
          mem.guaranteed <- TRUE
        }
      }
      
      if(cpu.guaranteed && mem.guaranteed) {
        qos.class <- "Guaranteed"
      } else {
        qos.class <- "Burstable"
      }
    }
    
    separate.socket.pol <- FALSE
    txtline <- yaml.content[grepl("socketpolicy:", yaml.content)]
    if(length(txtline) > 0) {
      separate.socket.pol.str <- trimws(strsplit(txtline, ":")[[1]][2])
      if(separate.socket.pol.str == "separate") {
        separate.socket.pol <- TRUE
      }
    }
    
    numaaware.numa.pol <- FALSE
    txtline <- yaml.content[grepl("numapolicy:", yaml.content)]
    if(length(txtline) > 0) {
      numaaware.numa.pol.str <- trimws(strsplit(txtline, ":")[[1]][2])
      if(numaaware.numa.pol.str == "numaaware") {
        numaaware.numa.pol <- TRUE
      }
    }
    
    stackposaware.stack.pol <- FALSE
    txtline <- yaml.content[grepl("stackpolicy:", yaml.content)]
    if(length(txtline) > 0) {
      stackposaware.stack.pol.str <- trimws(strsplit(txtline, ":")[[1]][2])
      if(stackposaware.stack.pol.str == "stackposaware") {
        stackposaware.stack.pol <- TRUE
      }
    }
    
    splitted.path <- strsplit(testdir, "/")[[1]]
    testdir.clean <- splitted.path[length(splitted.path)]
    testdir.clean.splitted <- strsplit(testdir.clean, "-")[[1]]
    benchmark.program <- testdir.clean.splitted[1]
    benchmark.input <- testdir.clean.splitted[2]
    
    test.df <- cbind(test.df,
                     benchmark.program = rep(benchmark.program, nrow(test.df)),
                     benchmark.input = rep(benchmark.input, nrow(test.df)),
                     qos.class = rep(qos.class, nrow(test.df)),
                     separate.socket.pol = rep(separate.socket.pol, nrow(test.df)),
                     numaaware.numa.pol = rep(numaaware.numa.pol, nrow(test.df)),
                     stackposaware.stack.pol = rep(stackposaware.stack.pol, nrow(test.df)))
    
    test.df
  }
  
  resultspath <- paste0(benchmarkpath, "/results")
  dirs <- list.dirs(resultspath, full.names = FALSE, recursive = FALSE)
  
  require(data.table)
  full.tests.df <- rbindlist(lapply(dirs, get.results.for.single.test, benchmarkpath))
  
  # Processing the results (~analysis)
  require(dplyr)
  require(magrittr)
  
  summary.test.results <- full.tests.df %>%
    dplyr::group_by(suite, benchmark.program, benchmark.input, qos.class, separate.socket.pol, numaaware.numa.pol, stackposaware.stack.pol) %>%
    dplyr::summarise(meantime = sum(timereal) / n(),
                     sdtime = sd(timereal))
  
  tests.combinations <- unique(data.frame(full.tests.df$benchmark.program, full.tests.df$benchmark.input))
  names(tests.combinations) <- c("benchmark.program", "benchmark.input")
  
  make.plots.for.given.test <- function(test.combination, full.tests.df, analysispath) {
    require(gtools)
    require(ggplot2)
    
    benchmark.program <- test.combination["benchmark.program"]
    benchmark.input <- test.combination["benchmark.input"]
    full.tests.df.filtered <- full.tests.df[(full.tests.df$benchmark.program == benchmark.program) & (full.tests.df$benchmark.input == benchmark.input), ]
    
    params.combinations <- as.data.frame(gtools::permutations(2, 3, c(TRUE, FALSE), repeats.allowed = TRUE))[2:8,]
    names(params.combinations) <- c("separate.socket.pol", "numaaware.numa.pol", "stackposaware.stack.pol")
    
    make.plot.for.given.config <- function(config.row, full.tests.df.filtered, analysispath, benchmark.program, benchmark.input) {
      separate.socket.pol <- as.logical(config.row["separate.socket.pol"])
      numaaware.numa.pol <- as.logical(config.row["numaaware.numa.pol"])
      stackposaware.stack.pol <- as.logical(config.row["stackposaware.stack.pol"])
      
      selector.l <- (full.tests.df.filtered$separate.socket.pol %in% separate.socket.pol) & (full.tests.df.filtered$numaaware.numa.pol %in% numaaware.numa.pol) & (full.tests.df.filtered$stackposaware.stack.pol %in% stackposaware.stack.pol)
      
      configured.data <- full.tests.df.filtered[selector.l,]
      if(nrow(configured.data) > 0) {
        configured.data$configuration <- rep("Configured", nrow(configured.data))
        
        selector.l.nullconf <- (full.tests.df.filtered$separate.socket.pol %in% FALSE) & (full.tests.df.filtered$numaaware.numa.pol %in% FALSE) & (full.tests.df.filtered$stackposaware.stack.pol %in% FALSE)
        baseline.data <- full.tests.df.filtered[selector.l.nullconf,]
        baseline.data$configuration <- rep("Not configured", nrow(baseline.data))
        
        data.to.plot <- rbind(baseline.data, configured.data)
        
        pic.name <- paste0(benchmark.program,
                           "-",
                           benchmark.input,
                           "-",
                           as.numeric(separate.socket.pol),
                           "-",
                           as.numeric(numaaware.numa.pol),
                           "-",
                           as.numeric(stackposaware.stack.pol),
                           ".png")
        
        png(filename=paste0(analysispath, "/", pic.name), width = 800, height = 800)
        print({
          ggplot(data.to.plot, aes(x=qos.class, y=timereal, fill=qos.class)) +
            geom_boxplot() +
            facet_wrap(~configuration) +
            labs(title = paste0("Runtime for ",
                           benchmark.program,
                           " with input ",
                           benchmark.input,
                           "\nand settings: Separate Sockets (",
                           separate.socket.pol,
                           "); NUMA-awareness (",
                           numaaware.numa.pol,
                           "); stack-pos-awareness (",
                           stackposaware.stack.pol,
                           ")"),
                 x = "Pod QoS Class",
                 y = "Runtime, s.",
                 fill = "Pod QoS Class")
        })
        dev.off()
      }
    }
    
    apply(params.combinations, 1, make.plot.for.given.config, full.tests.df.filtered, analysispath, benchmark.program, benchmark.input)
  }
  
  apply(tests.combinations, 1, make.plots.for.given.test, full.tests.df, analysispath)
  
  # Saving the data on disk as csv
  write.csv(full.tests.df, paste0(analysispath, "/rawtestresults.csv"), row.names = FALSE)
  write.csv(summary.test.results, paste0(analysispath, "/summarytestresults.csv"), row.names = FALSE)
  results <- list(rawtestresults = full.tests.df,
                  summarytestresults = summary.test.results)
  save(results, file = paste0(analysispath, "/results.RData"))
}

# TODO: make geometric mean of speedups based on https://www.eee.hku.hk/~elec3441/sp17/handouts/Fleming_Wallace_86.pdf