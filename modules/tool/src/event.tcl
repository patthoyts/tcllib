###
# This file implements the Tool event manager
###

::namespace eval ::tool {}

::namespace eval ::tool::event {}

###
# topic: f2853d380a732845610e40375bcdbe0f
# description: Cancel a scheduled event
###
proc ::tool::event::cancel {self {task *}} {
  variable timer_event
  variable timer_script

  foreach {id event} [array get timer_event $self:$task] {
    ::after cancel $event
    set timer_event($id) {}
    set timer_script($id) {}
  }
}

###
# topic: 8ec32f6b6ba78eaf980524f8dec55b49
# description:
#    Generate an event
#    Adds a subscription mechanism for objects
#    to see who has recieved this event and prevent
#    spamming or infinite recursion
###
proc ::tool::event::generate {self event args} {
  set wholist [Notification_list $self $event]
  if {$wholist eq {}} return
  set dictargs [::oo::meta::args_to_options {*}$args]
  set info $dictargs
  set strict 0
  set debug 0
  set sender $self
  dict with dictargs {}
  dict set info id     [::tool::event::nextid]
  dict set info origin $self
  dict set info sender $sender
  dict set info rcpt   {}
  foreach who $wholist {
    catch {::tool::event::notify $who $self $event $info}
  }
}

###
# topic: 891289a24b8cc52b6c228f6edb169959
# title: Return a unique event handle
###
proc ::tool::event::nextid {} {
  return "event#[format %0.8x [incr ::tool::event_count]]"
}

###
# topic: 1e53e8405b4631aec17f98b3e8a5d6a4
# description:
#    Called recursively to produce a list of
#    who recieves notifications
###
proc ::tool::event::Notification_list {self event {stackvar {}}} {
  set notify_list {}
  foreach {obj patternlist} [array get ::tool::object_subscribe] {
    if {$obj eq $self} continue
    if {$obj in $notify_list} continue
    set match 0
    foreach {objpat eventlist} $patternlist {
      if {![string match $objpat $self]} continue
      foreach eventpat $eventlist {
        if {![string match $eventpat $event]} continue
        set match 1
        break
      }
      if {$match} {
        break
      }
    }
    if {$match} {
      lappend notify_list $obj
    }
  }
  return $notify_list
}

###
# topic: b4b12f6aed69f74529be10966afd81da
###
proc ::tool::event::notify {rcpt sender event eventinfo} {
  if {[info commands $rcpt] eq {}} return 
  if {$::tool::trace} {
    puts [list event notify rcpt $rcpt sender $sender event $event info $eventinfo]
  }
  $rcpt notify $event $sender $eventinfo
}

###
# topic: 829c89bda736aed1c16bb0c570037088
###
proc ::tool::event::process {self handle script} {
  variable timer_event
  variable timer_script

  array unset timer_event $self:$handle
  array unset timer_script $self:$handle

  set err [catch {uplevel #0 $script} result errdat]
  if $err {
    puts "BGError: $self $handle $script
ERR: $result
[dict get $errdat -errorinfo]
***"
  }
}

###
# topic: eba686cffe18cd141ac9b4accfc634bb
# description: Schedule an event to occur later
###
proc ::tool::event::schedule {self handle interval script} {
  variable timer_event
  variable timer_script
  if {$::tool::trace} {
    puts [list $self schedule $handle $interval]
  }
  if {[info exists timer_event($self:$handle)]} {
    if {$script eq $timer_script($self:$handle)} {
      return
    }
    ::after cancel $timer_event($self:$handle)
  }
  set timer_script($self:$handle) $script
  set timer_event($self:$handle) [::after $interval [list ::tool::event::process $self $handle $script]]
}

proc ::tool::event::sleep msec {
  ::cron::sleep $msec
}

###
# topic: e64cff024027ee93403edddd5dd9fdde
###
proc ::tool::event::subscribe {self who event} {
  upvar #0 ::tool::object_subscribe($self) subscriptions
  if {![info exists subscriptions]} {
    set subscriptions {}
  }
  set match 0
  foreach {objpat eventlist} $subscriptions {
    if {![string match $objpat $who]} continue      
    foreach eventpat $eventlist {
      if {[string match $eventpat $event]} {
        # This rule already exists
        return
      }
    }
  }
  dict lappend subscriptions $who $event
}

###
# topic: 5f74cfd01735fb1a90705a5f74f6cd8f
###
proc ::tool::event::unsubscribe {self args} {
  upvar #0 ::tool::object_subscribe($self) subscriptions
  if {![info exists subscriptions]} {
    return
  }  
  switch [llength $args] {
    1 {
      set event [lindex $args 0]
      if {$event eq "*"} {
        # Shortcut, if the 
        set subscriptions {}
      } else {
        set newlist {}
        foreach {objpat eventlist} $subscriptions {
          foreach eventpat $eventlist {
            if {[string match $event $eventpat]} continue
            dict lappend newlist $objpat $eventpat
          }
        }
        set subscriptions $newlist
      }
    }
    2 {
      set who [lindex $args 0]
      set event [lindex $args 1]
      if {$who eq "*" && $event eq "*"} {
        set subscriptions {}
      } else {
        set newlist {}
        foreach {objpat eventlist} $subscriptions {
          if {[string match $who $objpat]} {
            foreach eventpat $eventlist {
              if {[string match $event $eventpat]} continue
              dict lappend newlist $objpat $eventpat
            }
          }
        }
        set subscriptions $newlist
      }
    }
  }
}

::tool::define ::tool::object {
  ###
  # topic: 20b4a97617b2b969b96997e7b241a98a
  ###
  method event {submethod args} {
    ::tool::event::$submethod [self] {*}$args
  }
}

###
# topic: 37e7bd0be3ca7297996da2abdf5a85c7
# description: The event manager for Tool
###
namespace eval ::tool::event {
  variable nextevent {}
  variable nexteventtime 0
}

