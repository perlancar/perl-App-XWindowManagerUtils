package App::XWindowManagerUtils;

use 5.010001;
use strict 'subs', 'vars';
use warnings;
use Log::ger;

use Exporter qw(import);
use IPC::System::Options 'system', -log=>1;

# AUTHORITY
# DATE
# DIST
# VERSION

our @EXPORT_OK = qw(
                       list_xwm_windows
               );

our %SPEC;

$SPEC{':package'} = {
    v => 1.1,
    summary => 'Utilities related to X Window Manager',
};

$SPEC{list_xwm_windows} = {
    v => 1.1,
    summary => "List all Windows",
    args => {
        query => {
            schema => ['array*', of=>'str*'],
            pos => 0,
            slurpy => 1,
        },
        detail => {
            schema => 'bool*',
            cmdline_aliases => {l=>{}},
        },
        with_kde_activity => {
            schema => 'bool*',
        },
    },
    deps => {
        prog => 'wmctrl',
    },
};
sub list_xwm_windows {
    my %args = @_;

    my $with_kde_activity = $args{with_kde_activity};
    my $detail = $args{detail};
    $detail //=1 if $with_kde_activity;

    my @rows;
    system({capture_stdout => \my $stdout}, "wmctrl", "-lpG");
    return [500, "Can't run wmctrl"] if $?;

    my @positive_query;
    my @negative_query;
  BUILD_QUERY: {
        for my $query (@{ $args{query} // [] }) {
            if ($query =~ /\A-(.*)/) {
                my $q = $1;
                push @negative_query, sub { $_[0] =~ /\Q$q\E/i ? 1 : 0 };
            } elsif ($query =~ m!\A/(.*)/\z!) {
                my $re = $1;
                push @positive_query, sub { $_[0] =~ /$re/i ? 1 : 0 };
            } else {
                push @positive_query, sub { $_[0] =~ /\Q$query\E/i ? 1 : 0 };
            }
        }
    } # BUILD_QUERY

  LINE:
    for my $line (split /^/m, $stdout) {
        my ($id, $desktop, $pid,
            $x, $y, $width, $height,
            $host, $title) = $line =~ /^(\S+)\s+(\S+)\s+(\d+)\s+
                                       (\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+
                                       (\S+)\s+(.*)/x;
        my $row = {
            id => $id,
            desktop => $desktop,
            pid => $pid,
            x => $x,
            y => $y,
            width => $width,
            height => $height,
            host => $host,
            title => $title,
        };

      FILTER: {
          NEGATIVE_QUERY: {
                last unless @negative_query;
                my $match = 1;
                for my $query (@negative_query) {
                    if ($query->($row->{title})) {
                        $match = 0; goto L1;
                    }
                }
              L1:
                unless ($match) {
                    log_trace "Skipping window id=%s title=<%s>: matches negative query in %s", $row->{id}, $row->{title}, $args{query};
                    next LINE;
                }
            }

          POSITIVE_QUERY: {
                last unless @positive_query;
                my $match = 1;
                for my $query (@positive_query) {
                    if (!$query->($row->{title})) {
                        $match = 0; goto L1;
                    }
                }

              L1:
                unless ($match) {
                    log_trace "Skipping window id=%s title=<%s>: does not match all positive query in %s", $row->{id}, $row->{title}, $args{query};
                    next LINE;
                }
            } # QUERY
        } # FILTER

      GET_KDE_ACTIVITY: {
            last unless $with_kde_activity;
            my $res_get_act = get_xwm_window_kde_activity(id => $row->{id});
            if ($res_get_act->[0] != 200) {
                log_warn "Can't get KDE activity for window id %s: %d - %s", $row->{id}, $res_get_act->[0], $res_get_act->[1];
                last;
            }
            $row->{kde_activity} = $res_get_act->[2];
        }

        push @rows, $row;
    } # for line

    unless ($args{detail}) {
        @rows = map { $_->{id} } @rows;
    }

    [200, "OK", \@rows];
}

$SPEC{get_xwm_window_kde_activity} = {
    v => 1.1,
    summary => "Get the KDE activity GUID(s) of a specific window",
    description => <<'MARKDOWN',

A window can be displayed in more than one KDE activities, so this utility can
return a comma-separated list of GUIDs.

MARKDOWN
    args => {
        id => {
            summary => 'Window ID, specified in hex form with 0x prefix, e.g. 0x05a0000e',
            schema => ['str*'],
            req => 1,
            pos => 0,
        },
    },
    deps => {
        all => [
            {prog => 'wmctrl'},
            {prog => 'xprop'},
        ],
    },
};
sub get_xwm_window_kde_activity {
    my %args = @_;

    my $id = $args{id} or return [400, "Please specify id"];

    system({capture_stdout => \my $stdout, capture_stderr => \my $stderr},
           "xprop", "-id", $id, "_KDE_NET_WM_ACTIVITIES");
    if ($?) {
        if ($stderr =~ /BadWindow.*invalid Window parameter/) {
            return [404, "No such window ID"];
        } else {
            return [500, "Can't successfully run xprop"];
        }
    } else {
        # sample output: _KDE_NET_WM_ACTIVITIES(STRING) = "40eabb80-2103-48af-8977-23b6e06fbcc3"
        my ($guid) = $stdout =~ /^_KDE_NET_WM_ACTIVITIES.+"([^"]+)"/;

        return [200, "OK", $guid];
    }
}

1;
# ABSTRACT:

=head1 SYNOPSIS

=head1 DESCRIPTION

This distribution includes several utilities related to X Window Manager:

#INSERT_EXECS_LIST


=head1 SEE ALSO
