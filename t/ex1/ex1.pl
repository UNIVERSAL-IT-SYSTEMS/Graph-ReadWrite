#!/usr/bin/perl -w

use strict;
use warnings;

use Graph;
use Graph::Reader::Dot;
use Graph::Writer::Verilog;

{
	my $nname       = 'ex1';

	my $reader      = Graph::Reader::Dot->new ();
	my $g           = $reader->read_graph ("${nname}.dot");

	$g->set_vertex_attributes('u2', {verilog => "\tassign i_0_dat = t_0_dat * t_1_dat;"});

	my $interface   = {'bundle' => {'default' => {'initiator' => {'req' => {}, 'dat' => {'width' => 8}}, 'target' => {'ack' => {}}}}};
	my $writer      = Graph::Writer::Verilog->new ($interface);
	$writer->write_graph ($g, "${nname}.v");
}
