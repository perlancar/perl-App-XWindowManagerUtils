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
    },
    deps => {
        prog => 'wmctrl',
    },
};
sub list_xwm_windows {
    my %args = @_;

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

        push @rows, $row;
    } # for line

    unless ($args{detail}) {
        @rows = map { $_->{id} } @rows;
    }

    [200, "OK", \@rows];
}

1;
# ABSTRACT:

=head1 SYNOPSIS

=head1 DESCRIPTION

This distribution includes several utilities related to X Window Manager:

#INSERT_EXECS_LIST


=head1 SEE ALSO
