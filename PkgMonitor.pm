package PkgMonitor;

use Moose;
use IPC::Cmd qw/can_run run/;

has 'log' => (
    is       => 'ro',
    isa      => 'Ref',
    required => 1,
);

has 'pkg_manager' => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
    default  => sub {
        my $self = shift;
        return $self->_get_pkg_manager();
    }
);

has 'parser' => (
    is  => 'rw',
    isa => 'Ref',
);

has 'pkglist' => (
    is      => 'rw',
    isa     => 'HashRef',
    default => sub {
        my $self = shift;
        return $self->_get_pkg_list();
    }
);

sub _get_pkg_manager {
    my ($self) = @_;

    if ( can_run('dpkg-query') ) {
        $self->parser( sub { return $self->dpkg_parser(@_); } );
        return can_run('dpkg-query') . ' --list';
    }
    elsif ( can_run('rpm') ) {
        $self->parser( sub { return $self->rpm_parser(@_); } );
        return can_run('rpm') . ' -qai';
    }
    else {
        die 'Can\'t find dpkg-query or rpm';
    }
}

sub _get_pkg_list {
    my ($self) = @_;

    return $self->parser->( $self->_run_command( $self->pkg_manager() ) ) || {};
}

sub pkg_state {
    my $self = shift;

    my $current_packages = $self->_get_pkg_list;
    my ( $new_packages, $removed_packages ) = {};

    foreach my $pkg ( keys %$current_packages ) {
        if ( !exists $self->pkglist->{$pkg} ) {
            $new_packages->{$pkg} = $current_packages->{$pkg};
        }
    }
    foreach my $pkg ( keys %{ $self->pkglist } ) {
        if ( !exists $current_packages->{$pkg} ) {
            $removed_packages->{$pkg} = $self->pkglist->{$pkg};
        }
    }
    $self->pkglist($current_packages);
    return {
        pkglist   => $current_packages,
        installed => $new_packages || {},
        removed   => $removed_packages || {},
    };
}

sub dpkg_parser {
    my ( $self, $buffer ) = @_;
    my $packages;

    return undef if not $buffer;

    my ( $state_len, $name_len, $version_len, $arch_len, $desc_len ) = 0;

    foreach my $line ( split( "\n", $buffer ) ) {

        next if $line =~ m/^Desired/;

        if ( $line =~ m/^\+\+\+/ ) {
            ( $state_len, $name_len, $version_len, $arch_len, $desc_len ) =
              map { length $_ } split '-', $line;
        }

        if ( $line =~ m/^\w/ ) {
            my $name    = _remove_space( substr $line, $state_len, $name_len );
            my $version = _remove_space(
                    substr $line, $state_len + $name_len, $version_len );
            my $arch    = _remove_space(
                    substr $line, $state_len + $name_len + $version_len, $arch_len );
            my $desc    = _remove_space(
                    substr $line, $state_len + $name_len + $version_len + $arch_len, $desc_len );

            $packages->{$name} = {
                name    => $name,
                version => $version,
                arch    => $arch,
                desc    => $desc,
            };

        }
    }

    return $packages;
}

sub rpm_parser {
    my ( $self, $buffer ) = @_;
    my $packages;

    return undef if not $buffer;
    $buffer =~ s/Name/NameName/g;

    foreach my $line ( split( "\nName", $buffer ) ) {

        next if not $line;

        chomp $line;
        my ( $version, $arch, $install_date, $desc, $name ) = '';

        foreach my $info ( split "\n", $line ) {
            my $title;

            if ( $info =~ m/^Version/ ) {
                ( $title, $version ) = split( ':', $info );
            }
            elsif ( $info =~ m/^Architecture/ ) {
                ( $title, $arch ) = split( ':', $info );
            }
            elsif ( $info =~ m/^Install Date/ ) {
                ( $title, $install_date ) = split( ':', $info );
            }
            elsif ( $info =~ m/^Summary/ ) {
                ( $title, $desc ) = split( ':', $info );
            }
            elsif ( $info =~ m/^Name/ ) {
                ( $title, $name ) = split( ':', $info );
            }
            next if not $name;

            $packages->{ _remove_space($name) } = {
                name         => _remove_space($name),
                version      => _remove_space($version),
                arch         => _remove_space($arch),
                desc         => _remove_space($desc),
                install_date => _remove_space($install_date)
            };
        }
    }
    return $packages;

}

sub _run_command {
    my ( $self, $command ) = @_;

    my ( $success, $error, $full_buf, $stdout_buf, $stderr_buf ) =
        run( command => $command );

    if ($success) {
        return join '', @$stdout_buf;
    }
    else {
        $self->log->error($self->pkg_manager . " returned $error");
    }
    return undef;
}

sub _remove_space {
    my $string = shift;

    $string =~ s/^\s|\s{2,}//g if $string;

    return $string;
}

__PACKAGE__->meta->make_immutable;
