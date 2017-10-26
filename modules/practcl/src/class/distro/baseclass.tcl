
###
# Standalone class to manage code distribution
# This class is intended to be mixed into another class
# (Thus the lack of ancestors)
###
oo::class create ::practcl::distribution {

  method DistroMixIn {} {
    my define set scm none
  }

  method Sandbox {} {
    if {[my define exists sandbox]} {
      return [my define get sandbox]
    }
    if {[my organ project] ni {::noop {}}} {
      set sandbox [my <project> define get sandbox]
      if {$sandbox ne {}} {
        my define set sandbox $sandbox
        return $sandbox
      }
    }
    set sandbox [file normalize [file join $::CWD ..]]
    my define set sandbox $sandbox
    return $sandbox
  }

  method SrcDir {} {
    set pkg [my define get name]
    if {[my define exists srcdir]} {
      return [my define get srcdir]
    }
    set sandbox [my Sandbox]
    set srcdir [file join [my Sandbox] $pkg]
    my define set srcdir $srcdir
    return $srcdir
  }

  method ScmTag    {} {}
  method ScmClone  {} {}
  method ScmUnpack {} {}
  method ScmUpdate {} {}

  method Unpack {} {
    set srcdir [my SrcDir]
    if {[file exists $srcdir]} {
      return
    }
    set pkg [my define get name]
    if {[my define exists download]} {
      # Utilize a staged download
      set download [my define get download]
      if {[file exists [file join $download $pkg.zip]]} {
        ::practcl::tcllib_require zipfile::decode
        ::zipfile::decode::unzipfile [file join $download $pkg.zip] $srcdir
        return
      }
    }
    my ScmUnpack
  }
}

oo::objdefine ::practcl::distribution {

  method Sandbox {object} {
    if {[$object define exists sandbox]} {
      return [$object define get sandbox]
    }
    if {[$object organ project] ni {::noop {}}} {
      set sandbox [$object <project> define get sandbox]
      if {$sandbox ne {}} {
        $object define set sandbox $sandbox
        return $sandbox
      }
    }
    set pkg [$object define get name]
    set sandbox [file normalize [file join $::CWD ..]]
    $object define set sandbox $sandbox
    return $sandbox
  }

  method select object {
    if {[$object define exists scm]} {
      return [$object define get scm]
    }

    set pkg [$object define get name]
    if {[$object define get srcdir] ne {}} {
      set srcdir [$object define get srcdir]
    } else {
      set srcdir [file join [my Sandbox $object] $pkg]
      $object define set srcdir $srcdir
    }

    set classprefix ::practcl::distribution.
    if {[file exists $srcdir]} {
      foreach class [::info commands ${classprefix}*] {
        if {[$class claim_path $srcdir]} {
          $object mixin distribution $class
          $object define set scm [string range $class [string length ::practcl::distribution.] end]
          return [$object define get scm]
        }
      }
    }
    foreach class [::info commands ${classprefix}*] {
      if {[$class claim_object $object]} {
        $object mixin distribution $class
        $object define set scm [string range $class [string length ::practcl::distribution.] end]
        return [$object define get scm]
      }
    }
    if {[$object define get scm] eq {} && [$object define exists file_url]} {
      set class ::practcl::distribution.snapshot
      $object define set scm snapshot
      $object mixin distribution $class
      return [$object define get scm]
    }
    error "Cannot determine source distribution method"
  }

  method claim_path path {
    return false
  }
  method claim_object object {
    return false
  }
}
