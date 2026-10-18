# SwiftPM can return success if a hostless AppKit test stops its main run loop.
# Every started Swift Testing run must report its terminal summary.
BEGIN { started = 0; finished = 0 }
/Test run started\./ { started++ }
/Test run with [0-9]+ tests?/ && /passed|failed/ { finished++ }
END {
    if (started == 0 || started != finished) {
        print "Native test verification incomplete: " started " runs started, " finished " finished." > "/dev/stderr"
        exit 1
    }
}
