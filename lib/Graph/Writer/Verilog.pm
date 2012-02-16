#
# Graph::Writer::Verilog - write a directed graph out in Verilog format
#
package Graph::Writer::Verilog;

use strict;
use warnings;

use POSIX;

use Data::Dumper;
use Sort::Naturally;

use Graph::Writer;
use vars qw(@ISA);

@ISA = qw(Graph::Writer);

my $param_format  = "\tparameter %-40s = %s";
my $inst_format   = "\t.%-40s(%s)";
my $assign_format = "\tassign %-40s = %s;";

my $interface; # interfaces description file

my $initiator_prefix = 'i'; # need good prefix !!!
my $target_prefix    = 't'; # need good prefix !!!

sub _init {
	my $self = shift;
	$interface = shift;
	$self->SUPER::_init();
}

sub _print_dim { # formated output for wire / port dimentions
	my $lformat = "%45s"; # long
	my $width = shift || return sprintf $lformat, '';
	if ($width =~ /^\d+$/) {
		if ($width == 0) { return sprintf $lformat, '0BUG!!!' }
		if ($width == 1) { return sprintf $lformat, '' }
		return sprintf $lformat, '[' . scalar $width - 1 . ':0]';
	}
	return sprintf $lformat, "[$width-1:0]";
}

sub _print_sys {
	my @RET;
	my $sys = shift || return \@RET;
	my @A = split (' ', $sys);
	for my $v (@A) {
		my @B = split ('=', $v);
		my ($from, $to) = @B;
		push @RET, sprintf $inst_format, $from, $to;
	}
	return \@RET;
}

sub _the_edge_attribute {
	my ($g, $v, $attr) = @_;
	my @e = ($g->edges_at($v));
	my @edge = (@{$e[0]}, $attr);
	return $g->get_edge_attribute(@edge);
}

sub _print_params { # all top level parameters
	my $g = shift;
	my @arr;

	for my $e ($g->edges) {
		my ($label, $type, $prefix, $from, $to, $from_label, $to_label);
		($from, $to) = @{$e};

		$from_label  = $g->get_vertex_attribute ($from, 'label') || $from;
		$to_label    = $g->get_vertex_attribute ($to,   'label') || $to;

		$type = $g->get_edge_attribute (@{$e}, 'label') || 'default';
		if     ($g->in_degree ($from) == 0) { # target socket
			$prefix = $target_prefix;
			$label  = $from_label;
		}
		elsif ($g->out_degree($to)   == 0) { # initiator socket
			$prefix = $initiator_prefix;
			$label  = $to_label;
		}
		else {                                 # internal edge
			$prefix = 'edge';
			$label  = "$from\_$to";
		}

		my @TMP = (
			$interface->{bundle}->{$type}->{initiator},
			$interface->{bundle}->{$type}->{target}
		);
		for my $tmp (@TMP) {
			if (defined $tmp) {
				for my $k (nsort keys %{$tmp}) {
					if (my $number = $tmp->{$k}->{width}) {
						my $width  = uc "$prefix\_$label\_$k\_width";
						push @arr, sprintf $param_format, $width, $number;
					}
				}
			}
		}
	}
	return join (",\n", @arr);
}

sub _print_sys_ports {
	my $g = shift;
	my @arr;
	my $width;
	for my $v (nsort $g->vertices) {
		if (($g->in_degree($v) == 0) || ($g->out_degree($v) == 0)) {
			my $sys = $g->get_vertex_attribute($v, 'sys');
			if (defined $sys) {
				for (split (' ', $sys)) {
					push @arr, "\tinput        " . _print_dim ($width) . " $_";
				}
			}
		}
	}
	if (scalar @arr) {
		return "// system signals\n" . join ( ",\n", @arr );
	}
}

sub _print_targets {  # all target nodes as ports of top module
	my $g = shift;
	my @arr;
	for my $v (nsort $g->vertices) {
		if (($g->in_degree($v) == 0) & ($g->out_degree($v) == 1)) {
			my $label = $g->get_vertex_attribute($v, 'label') || $v;
			my $type  = _the_edge_attribute ($g, $v, 'label') || 'default';
			push @arr, "\t\/\/ LABEL='$label', TYPE='$type'";
			if (defined (my $tmp = $interface->{bundle}->{$type}->{initiator})) {
				for my $k (nsort keys %{$tmp}) {
					my $width;
					if (defined $tmp->{$k}->{width}) {
						$width = uc "$target_prefix\_$label\_$k\_width";
					}
					push @arr, "\tinput  logic " . _print_dim ($width) . " $target_prefix\_$v\_$k";
				}
			}
			if (defined (my $tmp = $interface->{bundle}->{$type}->{target})) {
				for my $k (nsort keys %{$tmp}) {
					my $width;
					if (defined $tmp->{$k}->{width}) {
						$width = uc "$target_prefix\_$label\_$k\_width";
					}
					push @arr, "\toutput logic " . _print_dim ($width) . " $target_prefix\_$v\_$k";
				}
			}
		}
	}
	if (scalar @arr) {
		return "// target sockets\n" . join ( ",\n", @arr );
	}
}

sub _print_initiators {  # all initiator nodes as ports of top module
	my $g = shift;
	my @arr;
	for my $v ( nsort $g->vertices) {
		if(($g->in_degree($v) == 1) & ($g->out_degree($v) == 0 )) {
			my $label = $g->get_vertex_attribute($v, "label") || $v;
			my $type = _the_edge_attribute($g, $v, 'label')   || 'default';
			push @arr, "\t\/\/ LABEL='$label', TYPE='$type'";
			if (defined (my $branch = $interface->{bundle}->{$type}->{initiator})) {
				for my $k (nsort keys %{$branch}) {
					my $width;
					if (defined $branch->{$k}->{width}) {
						$width = uc "$initiator_prefix\_$label\_$k\_width";
					}
					push @arr, "\toutput logic " . _print_dim ($width) . " $initiator_prefix\_$v\_$k";
				}
			}
			if (defined (my $branch = $interface->{bundle}->{$type}->{target})) {
				for my $k (nsort keys %{$branch}) {
					my $width;
					if (defined $branch->{$k}->{width}) {
						$width = uc "$initiator_prefix\_$label\_$k\_width";
					}
					push @arr, "\tinput  logic " . _print_dim ($width) . " $initiator_prefix\_$v\_$k";
				}
			}
		}
	}
	return "// initiator sockets\n" . join ( ",\n", @arr );
}

sub _print_edges {
	my $g = shift;
	my %wire;

	for my $e (sort $g->edges) {
		if (($g->in_degree(${$e}[0]) > 0) & (($g->out_degree(${$e}[1])) > 0)) { # internal edge
			my $edge = join "_", @{$e}; # edge ID
			my $type = $g->get_edge_attribute(@{$e}, 'label') || 'default'; # edge type
			if (defined (my $branch = $interface->{bundle}->{$type}->{initiator})) {
				for my $k (nsort keys %{$branch}) {
					my $width;
					if (defined $branch->{$k}->{width}) {
						$width = uc "edge_$edge\_$k\_width";
					}
					$wire{"$edge\_$k"} = $width;
				}
			}
			if (defined (my $branch = $interface->{bundle}->{$type}->{target})) {
				for my $k ( nsort keys %{$branch}) {
					$wire{"$edge\_$k"} = $branch->{$k}->{width};
				}
			}
		}
	}
	my @ret;
	for my $k ( nsort keys %wire ) {
		push @ret, ( "\tlogic " . _print_dim ( $wire{$k} ) . " edge_" . $k . ";" );
	}
	return "// internal wires\n" . join ("\n", @ret );
}

sub _print_alias {
	my $g = shift;
	my $ret;
{
	my @alias;
	for my $v (sort $g->vertices) {
		if(($g->in_degree($v) == 0) & ($g->out_degree($v) == 1 )) {
			my @e = ($g->edges_from($v));
			my $e = join("_", @{$e[0]});
			my $type = _the_edge_attribute($g, $v, 'label') || 'default';
			if (defined($interface->{bundle}->{$type}->{initiator})) {
				for my $k ( nsort keys %{$interface->{bundle}->{$type}->{initiator}} ) {
					push @alias, sprintf ( $assign_format, "edge_$e\_$k", "$target_prefix\_$v\_$k" );
				}
			}
			if (defined($interface->{bundle}->{$type}->{target})) {
				for my $k ( nsort keys %{$interface->{bundle}->{$type}->{target}}) {
					push @alias, sprintf ( $assign_format, "$target_prefix\_$v\_$k", "edge_$e\_$k" );
				}
			}
		}
	}
	$ret = "// target socket assigns\n" . join ( "\n", @alias );
}
{
	my @alias = '';
	for my $v ($g->vertices) {
		if(($g->in_degree($v) == 1) & ($g->out_degree($v) == 0 )) {
			my @e    = ( $g->edges_to($v) );
			my $e    = join ( "_", @{$e[0]} );
			my $type = _the_edge_attribute($g, $v, 'label') || 'default';
			my $tree = $interface->{bundle}->{$type};
			my $branch;
			if ( defined ( $branch = $tree->{initiator} ) ) {
				for my $k ( nsort keys %{ $branch }) {
					push @alias, sprintf ( $assign_format, "$initiator_prefix\_$v\_$k", "edge_$e\_$k" );
				}
			}
			if ( defined ( $branch = $tree->{target} ) ) {
				for my $k ( nsort keys %{ $branch } ) {
					push @alias, sprintf ( $assign_format, "edge_$e\_$k", "$initiator_prefix\_$v\_$k" );
				}
			}
		}
	}
	$ret .= "\n// initiator socket assigns\n" . join ( "\n", @alias );
}
	return $ret;
}

sub byheadlabel {
	my $g = shift;
	my $alabel = $g->get_edge_attribute(@{$a}, 'headlabel') || 0;
	my $blabel = $g->get_edge_attribute(@{$b}, 'headlabel') || 0;
	$alabel cmp $blabel;
}

sub bytaillabel {
	my $g = shift;
	my $alabel = $g->get_edge_attribute(@{$a}, 'taillabel') || 0;
	my $blabel = $g->get_edge_attribute(@{$b}, 'taillabel') || 0;
	$alabel cmp $blabel;
}

sub _print_units {
	my ($g, $prefix) = @_;
	my $ret;
{
	$ret = "// Units\n";
	for my $v (nsort $g->vertices) {
		if (($g->in_degree($v) > 0) & ($g->out_degree($v) > 0 )) {
			my (@iports, @iparams, @edges_to, @param_to, @edges_from, @param_from);

			for my $e (sort {byheadlabel($g)} $g->edges_to($v)) {
				my $label = $g->get_edge_attribute(@{$e}, 'headlabel') || 0;
				my $type  = $g->get_edge_attribute(@{$e}, 'label')     || 'default';
				push @edges_to, "// LABEL='$label', TYPE='$type'";
				push @iports,   "// LABEL='$label', TYPE='$type'";
				if (defined (my $tmp = $interface->{bundle}->{$type}->{target})) {
					for my $k (nsort keys %{$tmp}) {
						my $edge;
						my $from = ${$e}[0];
						if ($g->in_degree($from) == 0) {
							$edge = "$target_prefix\_$from\_$k";
						} else {
							$edge = 'edge_' . join ('_', @{$e}) . "_$k";
						}
						my $width;
						if (my $wire_width = $tmp->{$k}->{width}) {
							$width = uc "$target_prefix\_$label\_$k\_width";
							push @iparams, sprintf $param_format, $width, $wire_width;
							push @param_to, sprintf $inst_format, uc "$target_prefix\_$label\_$k\_width", uc ($edge . "_width");
						}
						push @edges_to, sprintf $inst_format,    "$target_prefix\_$label\_$k",           $edge;
						push @iports, "\toutput logic " . _print_dim($width) . " $target_prefix\_$label\_$k";
					}
				}
				if (defined (my $tmp = $interface->{bundle}->{$type}->{initiator})) {
					for my $k ( nsort keys %{$tmp}) {
						my $edge;
						my $to = ${$e}[0];
						if ($g->in_degree($to) == 0) {
							$edge = "$target_prefix\_$to\_$k";
						} else {
							$edge = 'edge_' . join ('_', @{$e}) . "_$k";
						}
						my $width;
						if (my $wire_width = $tmp->{$k}->{width}) {
							$width = uc "$target_prefix\_$label\_$k\_width";
							push @iparams, sprintf $param_format, $width, $wire_width;
							push @param_to, sprintf $inst_format, uc "$target_prefix\_$label\_$k\_width", uc ($edge . "_width");
						}
						push @edges_to, sprintf $inst_format,    "$target_prefix\_$label\_$k",           $edge;
						push @iports, "\tinput  logic " . _print_dim($width) . " $target_prefix\_$label\_$k";
					}
				}
			}
			for my $e ( sort { bytaillabel($g) } $g->edges_from($v)) {
				my $label = $g->get_edge_attribute(@{$e}, 'taillabel') || 0;
				my $type  = $g->get_edge_attribute(@{$e}, 'label') || 'default';
				push @edges_from, "// LABEL='$label', TYPE='$type'";
				push @iports,     "// LABEL='$label', TYPE='$type'";
				if (defined($interface->{bundle}->{$type}->{target})) {
					for my $k ( nsort keys %{$interface->{bundle}->{$type}->{target}}) {
						my $edge;
						my $to = ${$e}[1];
						if ($g->out_degree($to) == 0) {
							$edge = "$initiator_prefix\_$to\_$k";
						} else {
							$edge = 'edge_' . join ('_', @{$e}) . "_$k";
						}
						my $width;
						if (my $wire_width = $interface->{bundle}->{$type}->{target}->{$k}->{width}) {
							$width = uc "$initiator_prefix\_$label\_$k\_width";
							push @iparams,   sprintf $param_format, $width, $wire_width;
							push @param_from, sprintf $inst_format, uc "$initiator_prefix\_$label\_$k\_width", uc ($edge . "_width");
						}
						push @edges_from, sprintf $inst_format,    "$initiator_prefix\_$label\_$k",           $edge;
						push @iports, "\tinput  logic " . _print_dim($width) . " $initiator_prefix\_$label\_$k";
					}
				}
				if (defined($interface->{bundle}->{$type}->{initiator})) {
					for my $k ( nsort keys %{$interface->{bundle}->{$type}->{initiator}}) {
						my $edge;
						my $from = ${$e}[1];
						if ($g->out_degree($from) == 0) {
							$edge = "$initiator_prefix\_$from\_$k";
						} else {
							$edge = 'edge_' . join ('_', @{$e}) . "_$k";
						}
						my $width;
						if (my $wire_width = $interface->{bundle}->{$type}->{initiator}->{$k}->{width}) {
							$width = uc "$initiator_prefix\_$label\_$k\_width";
							push @iparams,   sprintf $param_format, $width, $wire_width;
							push @param_from, sprintf $inst_format, uc "$initiator_prefix\_$label\_$k\_width", uc ($edge . "_width");
						}
						push @edges_from, sprintf $inst_format,    "$initiator_prefix\_$label\_$k",           $edge;
						push @iports, "\toutput logic " . _print_dim($width) . " $initiator_prefix\_$label\_$k";
					}
				}
			}
			my $sys      = $g->get_vertex_attribute ($v, 'sys');
			   $sys      = _print_sys ($sys);

			my $param    = $g->get_vertex_attribute ($v, 'param');
			   $param    = _print_sys ($param);

			my $unittype = $g->get_vertex_attribute ($v, 'label') || $v;
			   $unittype = $prefix . $unittype;

			$ret .= <<EOM;

$unittype #(
@{[ join ( ",\n", ( @{$param}, @param_to, @param_from ) ) ]}
) u_$v (
@{[ join ( ",\n", ( @{$sys}, @edges_to, @edges_from ) ) ]}
);
EOM

			my $verilog_text   = $g->get_vertex_attribute($v, 'verilog') || '';
			my $verilog_ports  = $g->get_vertex_attribute($v, 'verilog_ports') || '';
			my $verilog_header = $g->get_vertex_attribute($v, 'verilog_header') || '';
			my $pragmas  = '';
			my $inputs   = '// no system inputs';
			my $outputs  = '// no system outputs';
			my $vparams  = '// no system parameters';

			open  UNIT, ">$unittype.v" or die "Can't open output file $!";
			print UNIT <<EOM;
$verilog_header
module $unittype #(
$vparams
@{[ join(",\n", @iparams) ]}
) (
$verilog_ports
@{[ join(",\n", @iports ) ]}
)$pragmas;
$verilog_text
endmodule \/\/ $unittype

// -------------------------------------------------------------------
EOM
			close UNIT;
		}
	}
}
	return $ret;
}

sub _write_graph { # main write cycle
	my $self = shift;
	my $g    = shift;
	my $FILE = shift;

	my $ret;
	my $prefix = '';
	my $name = $g->get_graph_attributes();
	my $key = 'name';
	my $top_vbody = '';
	my $top_ports = '';

	$name = $$name{$key};

	my $inputs   = '// no system inputs';
	my $outputs  = '// no system outputs';
	my $vparams  = "// no system parameters\n";
	my $vbody = '';
	if (-e ('proj/' . $name . '.vt')) {
		print "Template found: $name\.vt\n";
		open my $oldout, ">&STDOUT" or die "Can't dup STDOUT: $!";
		close STDOUT;
		open  STDOUT, '>', \$vbody or die "Can't open vbody: $!";
#		eval (vbody ($name));

		if (ref $vparams) {
			my $tmp = $vparams;
			$vparams = '';
			for my $i (@{$tmp}) {
				my @TMP = split (' ', $i);
				$vparams .= sprintf "\tparameter %s = %s,\n", $TMP[0], $TMP[1];
			}
		}

		if (ref $inputs) {
			my $tmp = $inputs;
			$inputs = '';
			for my $i (@{$tmp}) {
				my @TMP = split (' ', $i);
				$inputs  .= sprintf "\tinput        %s %s,\n", _print_dim($TMP[1]), $TMP[0];
			}
		}

		if (ref $outputs) {
			my $tmp = $outputs;
			$outputs = '';
			for my $i (@{$tmp}) {
				my @TMP = split (' ', $i);
				$outputs .= sprintf "\toutput       %s %s,\n", _print_dim($TMP[1]), $TMP[0];
			}
		}

				close STDOUT;
		open  STDOUT, '>&', $oldout or die "Can't redup STDOUT\n";
		close $oldout;
		$top_ports .= $inputs  . "\n";
		$top_ports .= $outputs . "\n";
		$top_vbody .= $vbody;
	}
	$vparams .= _print_params ($g);

# top module print
$ret .= "\nmodule $name #(\n";
$ret .= $vparams;
$ret .= "\n) (\n";
$ret .= $top_ports;
$ret .= (_print_sys_ports ($g) ? (_print_sys_ports ($g) . ",\n") : '');
$ret .= (_print_targets   ($g) ? (_print_targets   ($g) . ",\n") : '');
$ret .= _print_initiators( $g );
$ret .= "\n);";
$ret .= _print_edges ($g) . "\n";
# $ret.= _print_alias ($g) . "\n";
$ret .= _print_units ($g, $prefix) . "\n";
$ret .= $top_vbody;
$ret .= <<EOM;

endmodule \/\/ $name

// -------------------------------------------------------------------
EOM
	print $FILE $ret;
	return 1;
}

1;

__END__

=head1 NAME

Graph::Writer::Verilog - write out directed graph in Verilog format

=head1 SYNOPSIS

	use Graph;
	use Graph::Writer::Verilog;

	$graph = Graph->new();
	# add edges and nodes to the graph

	$writer = Graph::Writer::Verilog->new();
	$writer->write_graph($graph, 'mygraph.v');

=head1 DESCRIPTION

B<Graph::Writer::Verilog> is a class for writing out a directed graph
in the Verilog RTL file format used by HDL design tools.
The graph must be an instance of the Graph class, which is
actually a set of classes developed by Jarkko Hietaniemi.

=head1 METHODS

=head2 new()

Constructor - generate a new writer instance.

	$writer = Graph::Writer::Verilog->new();

This doesn't take any arguments.

=head2 write_graph()

Write a specific graph to a named file:

	$writer->write_graph($graph, $file);

The C<$file> argument can either be a filename,
or a filehandle for a previously opened file.

=head1 SEE ALSO

=over 3

=item Graph

Jarkko Hietaniemi's modules for representing directed graphs,
available from CPAN under modules/by-module/Graph/

=item Graph::Writer

The base-class for Graph::Writer::Verilog

=back

=head1 AUTHOR

2012 Aliaksei Chapyzhenka E<lt>aliaksei.chapyzhenka@gmail.comE<gt>

This script is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
