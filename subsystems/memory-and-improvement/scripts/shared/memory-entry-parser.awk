BEGIN {
    reset_entry()
}

function reset_entry() {
    id = ""
    logged = ""
    priority = ""
    status = ""
    summary = ""
    recurrence = "0"
    in_summary = 0
}

function flush_entry() {
    if (id != "" && summary != "") {
        print id "\t" logged "\t" priority "\t" status "\t" summary "\t" recurrence
    }
    reset_entry()
}

/^## \[/ {
    flush_entry()
    id = $0
    sub(/^## \[/, "", id)
    sub(/\].*$/, "", id)
    next
}

/^\*\*Logged\*\*: / {
    logged = substr($0, 13)
    next
}

/^\*\*Priority\*\*: / {
    priority = substr($0, 15)
    next
}

/^\*\*Status\*\*: / {
    status = substr($0, 13)
    next
}

/^### (Summary|Requested Capability)$/ {
    in_summary = 1
    next
}

in_summary == 1 && summary == "" && $0 !~ /^[[:space:]]*$/ {
    summary = $0
    in_summary = 0
    next
}

/^- Recurrence-Count: / {
    recurrence = substr($0, 21)
    next
}

END {
    flush_entry()
}
