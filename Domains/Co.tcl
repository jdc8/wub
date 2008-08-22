# Co.tcl - a domain built around coroutines from tcl8.6

# import the relevant commands
namespace eval ::tcl::unsupported {namespace export coroutine yield}
namespace import ::tcl::unsupported::coroutine ::tcl::unsupported::yield

package require Http
package require Debug
Debug off co 10

package require md5

package provide Co 1.0

namespace eval Co {
    variable uniq [pid]	;# seed for unique coroutine names

    # give a uniq looking name
    proc uniq {} {
	variable uniq
	return [::md5::md5 -hex [incr uniq]]
    }

    # yield wrapper with command dispatcher
    proc yield {{retval ""}} {
	set yield [::yield $retval]
	Debug.co {yield ($retval) -> ($yield)}
	lassign $yield cmd args
	switch -- $cmd {
	    kill {
		return -code return $args
	    }

	    call -
	    default {
		return $args
	    }
	}
    }

    # process request
    proc _do {prefix lambda r} {
	# compute suffix
	if {[dict exists $r -suffix]} {
	    # caller has munged path already
	    set suffix [dict get $r -suffix]
	    Debug.co {-suffix given $suffix}
	} else {
	    # assume we've been parsed by package Url
	    # remove the specified prefix from path, giving suffix
	    set path [dict get $r -path]
	    set suffix [Url pstrip $prefix $path]
	    Debug.co {-suffix not given - calculated '$suffix' from '$prefix' and '$path'}
	    if {($suffix ne "/") && [string match "/*" $suffix]} {
		# path isn't inside our domain suffix - error
		return [Http NotFound $r "no such thing: $suffix"]
	    }
	}

	if {$suffix eq "/"} {
	    # this is a new call - create the coroutine
	    set cmd [uniq]
	    set result [coroutine $cmd ::apply [list {*}$lambda ::Co] $r]
	    if {$result ne ""} {
		Debug.co {coroutine initialised - ($r) reply}
		return $result	;# allow coroutine lambda to reply
	    } else {
		# otherwise redirect to coroutine lambda
		Debug.co {coroutine initialised - redirect to $cmd}
		return [Http Redirect $r $cmd]
	    }
	} elseif {[llength [info command ::Co::$suffix]]} {
	    # this is an existing coroutine - call it and return result
	    Debug.co {calling coroutine $suffix}
	    set result [$suffix [list call $r]]
	    Debug.co {coroutine yielded: ($result)}
	    return $result
	} else {
	    return [Http NotFound $r "no such co '$suffix'"]
	}
    }

    # initialize view ensemble for Co
    proc init {cmd prefix lambda args} {
	if {$args ne {}} {
	    variable {*}$args
	}
	set cmd [uplevel 1 namespace current]::$cmd
	namespace ensemble create \
	    -command $cmd -subcommands {} \
	    -map [list do [list _do $prefix $lambda]]
	return $cmd
    }

    namespace export -clear *
    namespace ensemble create -subcommands {}
}
