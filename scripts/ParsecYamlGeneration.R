#!/usr/bin/env Rscript
# Reference: http://parsec.cs.princeton.edu/doc/man/man7/parsec.7.html
# Execution format for the command line:
# Rscript ParsecLogsAnalysis.R
# --templatefile=scripts/template.yaml
# --yamldir=benchmarks/parsec
# --programs=blackscholes,bodytrack
# --sizes=simdev,simsmall
# --qos=besteffort,burstable,guaranteed
# --labels=separate,numaaware,stackposaware
# --gu.requests=0.5,4Gi
# --gu.limits=0.5,4Gi
# --bu.requests=0.5,4Gi
# --bu.limits=1,8Gi

# Tests:
# templatefile <- "D:/@TUM/UCC-2019/code/kubernetes/scripts/template.yaml"
# yamldir <- "D:/@TUM/UCC-2019/code/kubernetes/benchmarks/parsec"

# NOTE: it is advisable to select either one program or one size of the data ->
# otherwise the full options set to consider is estimated at 1560.

programs.def <- c("blackscholes",
                  "bodytrack",
                  "canneal",
                  "dedup",
                  "facesim",
                  "ferret",
                  "fluidanimate",
                  "freqmine",
                  "raytrace",
                  "streamcluster",
                  "swaptions",
                  "vips",
                  "x264")

sizes.def <- c("simdev",
               "simsmall",
               "simmedium",
               "simlarge",
               "native")

qos.def <- c("besteffort")

labels.def <- c("separate",
                "numaaware",
                "stackposaware")


templatefile.prefix <- "--templatefile="
yamldir.prefix <- "--yamldir="
programs.prefix <- "--programs="
sizes.prefix <- "--sizes="
qos.prefix <- "--qos="
labels.prefix <- "--labels="
bu.requests.prefix <- "--bu.requests="
bu.limits.prefix <- "--bu.limits="
gu.requests.prefix <- "--gu.requests="
gu.limits.prefix <- "--gu.limits="


templatefile <- cmd.args[which(grepl(templatefile.prefix, cmd.args))]
yamldir <- cmd.args[which(grepl(yamldir.prefix, cmd.args))]
programs <- cmd.args[which(grepl(programs.prefix, cmd.args))]
sizes <- cmd.args[which(grepl(sizes.prefix, cmd.args))]
qos <- cmd.args[which(grepl(qos.prefix, cmd.args))]
labels <- cmd.args[which(grepl(labels.prefix, cmd.args))]
bu.requests <- cmd.args[which(grepl(bu.requests.prefix, cmd.args))]
bu.limits <- cmd.args[which(grepl(bu.limits.prefix, cmd.args))]
gu.requests <- cmd.args[which(grepl(gu.requests.prefix, cmd.args))]
gu.limits <- cmd.args[which(grepl(gu.limits.prefix, cmd.args))]

if((length(templatefile) == 0) || (length(yamldir) == 0)) {
  print("Necessary parameters were not specified! Exiting.")
} else {
  
  templatefile <- substring(templatefile,
                            nchar(templatefile.prefix) + 1,
                            nchar(templatefile))
  
  yamldir <- substring(yamldir,
                       nchar(yamldir.prefix) + 1,
                       nchar(yamldir))
  
  if(length(programs) == 0) {
    programs <- programs.def
  } else {
    programs <- substring(programs,
                          nchar(programs.prefix) + 1,
                          nchar(programs))
  }
  
  if(length(sizes) == 0) {
    sizes <- sizes.def
  } else {
    sizes <- substring(sizes,
                       nchar(sizes.prefix) + 1,
                       nchar(sizes))
  }
  
  if(length(qos) == 0) {
    qos <- qos.def
  } else {
    qos <- substring(qos,
                     nchar(qos.prefix) + 1,
                     nchar(qos))
  }
  
  if(length(labels) == 0) {
    labels <- labels.def
  } else {
    labels <- substring(labels,
                        nchar(labels.prefix) + 1,
                        nchar(labels))
  }
  
  separate.socket.pol <- c(FALSE)
  if("separate" %in% labels) {
    separate.socket.pol <- c(TRUE, FALSE)
  }
  
  numaaware.numa.pol <- c(FALSE)
  if("numaaware" %in% labels) {
    numaaware.numa.pol <- c(TRUE, FALSE)
  }
  
  stackposaware.stack.pol <- c(FALSE)
  if("stackposaware" %in% labels) {
    stackposaware.stack.pol <- c(TRUE, FALSE)
  }
  
  bu.res <- NULL
  
  if(("burstable" %in% qos) && ((length(bu.requests) == 0) || (length(bu.limits) == 0))) {
    print("burstable limits and requests should be set if QoS class is burstable!")
    quit(status=1)
  } else {
    
    bu.requests <- substring(bu.requests,
                             nchar(bu.requests.prefix) + 1,
                             nchar(bu.requests))
    
    bu.limits <- substring(bu.limits,
                           nchar(bu.limits.prefix) + 1,
                           nchar(bu.limits))
    
    bu.requests.v <- strsplit(bu.requests, ",")[[1]]
    bu.req.cpu <- bu.requests.v[1]
    bu.req.mem <- bu.requests.v[2]
    
    bu.limits.v <- strsplit(bu.limits, ",")[[1]]
    bu.lim.cpu <- bu.limits.v[1]
    bu.lim.mem <- bu.limits.v[2]
    
    bu.res <- list(bu.req.cpu = bu.req.cpu,
                   bu.req.mem = bu.req.mem,
                   bu.lim.cpu = bu.lim.cpu,
                   bu.lim.mem = bu.lim.mem)
    
  }
  
  gu.res <- NULL
  
  if(("guaranteed" %in% qos) && ((length(gu.requests) == 0) || (length(gu.limits) == 0))) {
    print("guaranteed limits and requests should be set if QoS class is guaranteed!")
    quit(status=1)
  } else {
    
    gu.requests <- substring(gu.requests,
                             nchar(gu.requests.prefix) + 1,
                             nchar(gu.requests))
    
    gu.limits <- substring(gu.limits,
                           nchar(gu.limits.prefix) + 1,
                           nchar(gu.limits))
    
    gu.requests.v <- strsplit(gu.requests, ",")[[1]]
    gu.req.cpu <- gu.requests.v[1]
    gu.req.mem <- gu.requests.v[2]
    
    gu.limits.v <- strsplit(gu.limits, ",")[[1]]
    gu.lim.cpu <- gu.limits.v[1]
    gu.lim.mem <- gu.limits.v[2]
    
    gu.res <- list(gu.req.cpu = gu.req.cpu,
                   gu.req.mem = gu.req.mem,
                   gu.lim.cpu = gu.lim.cpu,
                   gu.lim.mem = gu.lim.mem)
    
  }

  options <- list(program = programs,
                  size = sizes,
                  qos = qos,
                  separate.socket.pol = separate.socket.pol,
                  numaaware.numa.pol = numaaware.numa.pol,
                  stackposaware.stack.pol = stackposaware.stack.pol)
  
  options.grid <- expand.grid(options)
  
  require(readr)
  template <- read_file(templatefile)
  
  # Going through the options and generating appropriate file based on the teplate
  generate.yaml <- function(option, template, yamldir, bu.res = NULL, gu.res = NULL) {
    template.filled <- template
    
    program <- option["program"]
    size <- option["size"]
    qos <- option["qos"]
    separate.socket.pol <- as.logical(trimws(option["separate.socket.pol"]))
    numaaware.numa.pol <- as.logical(trimws(option["numaaware.numa.pol"]))
    stackposaware.stack.pol <- as.logical(trimws(option["stackposaware.stack.pol"]))
    
    yamlname <- paste0(program, "-", size, "-", qos, "-", as.numeric(separate.socket.pol), "-", as.numeric(numaaware.numa.pol), "-", as.numeric(stackposaware.stack.pol), ".yaml")
    
    # Filling into the labels section
    labels.txt <- ""
    if(separate.socket.pol || numaaware.numa.pol || stackposaware.stack.pol) {
      labels.txt <- "labels:\r\n"
      
      if(separate.socket.pol) {
        labels.txt <- paste0(labels.txt, "    socketpolicy: separate\r\n")
      }
      
      if(numaaware.numa.pol) {
        labels.txt <- paste0(labels.txt, "    numapolicy: numaaware\r\n")
      }
      
      if(stackposaware.stack.pol) {
        labels.txt <- paste0(labels.txt, "    stackpolicy: stackposaware\r\n")
      }
    }
    
    template.filled <- gsub("<<labels>>", labels.txt, template.filled)
    
    # Filling into the parameters of the benchmark suite call
    template.filled <- gsub("<<program>>", program, template.filled)
    template.filled <- gsub("<<size>>", size, template.filled)
    
    # Filling into the resources section
    resources.txt <- ""
    if(qos %in% c("guaranteed", "burstable")) {
      resources.txt <- "resources:\r\n"
      
      if((qos == "burstable") && !is.null(bu.res)) {
        resources.txt <- paste0(resources.txt, "      requests:\r\n")
        resources.txt <- paste0(resources.txt, "        cpu: \"", bu.res$bu.req.cpu, "\"\r\n")
        resources.txt <- paste0(resources.txt, "        memory: \"", bu.res$bu.req.mem, "\"\r\n")
        resources.txt <- paste0(resources.txt, "      limits:\r\n")
        resources.txt <- paste0(resources.txt, "        cpu: \"", bu.res$bu.lim.cpu, "\"\r\n")
        resources.txt <- paste0(resources.txt, "        memory: \"", bu.res$bu.lim.mem, "\"\r\n")
      } else if((qos == "guaranteed") && !is.null(gu.res)) {
        resources.txt <- paste0(resources.txt, "      requests:\r\n")
        resources.txt <- paste0(resources.txt, "        cpu: \"", gu.res$gu.req.cpu, "\"\r\n")
        resources.txt <- paste0(resources.txt, "        memory: \"", gu.res$gu.req.mem, "\"\r\n")
        resources.txt <- paste0(resources.txt, "      limits:\r\n")
        resources.txt <- paste0(resources.txt, "        cpu: \"", gu.res$gu.lim.cpu, "\"\r\n")
        resources.txt <- paste0(resources.txt, "        memory: \"", gu.res$gu.lim.mem, "\"\r\n")
      }
    }
    template.filled <- gsub("<<resources>>", resources.txt, template.filled)
    
    # Writing the filled template
    write_file(template.filled, paste0(yamldir, "/", yamlname))
  }
  
  eee <- apply(options.grid, 1, generate.yaml, template, yamldir, bu.res, gu.res)  
}