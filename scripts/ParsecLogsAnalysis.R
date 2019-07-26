benchmarkpath <- "D:/@TUM/UCC-2019/code/kubernetes/benchmarks/parsec"




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
  
  benchmark.program <- trimws(strsplit(log.content[grepl("Benchmarks to run:", log.content)], ":")[[1]][2])
  benchmark.input <- trimws(strsplit(log.content[grepl("Unpacking benchmark input", log.content)], "'")[[1]][2])
  
  optionsnum <- as.numeric(trimws(strsplit(log.content[grepl("Num of Options", log.content)], ":")[[1]][2]))
  runsnum <- as.numeric(trimws(strsplit(log.content[grepl("Num of Runs", log.content)], ":")[[1]][2]))
  datasize <- as.numeric(trimws(strsplit(log.content[grepl("Size of data", log.content)], ":")[[1]][2]))
  
  timereal.str <- log.content[grepl("real\t", log.content)]
  timeuser.str <- log.content[grepl("user\t", log.content)]
  timesys.str <- log.content[grepl("sys\t", log.content)]
  
  timereal <- get.execution.time.from.string(timereal.str)
  timeuser <- get.execution.time.from.string(timeuser.str)
  timesys <- get.execution.time.from.string(timesys.str)
  
  data.frame(suite = "parsec",
             benchmark.program = benchmark.program,
             benchmark.input = benchmark.input,
             testrunid = testrunid,
             optionsnum = optionsnum,
             runsnum = runsnum,
             datasize = datasize,
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
  
  test.df <- cbind(test.df,
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