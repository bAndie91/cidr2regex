#!/usr/bin/env perl

use Number::Range::Regex;
Number::Range::Regex->init({'comment'=>0, 'no_leading_zeroes'=>1, 'no_sign'=>1});
use List::MoreUtils qw/any all/;
$|++;


$rr0_255 = range(0, 255);
$rr0_32 = range(0, 32);
$af_length = 32;
$octet_max = 255;

$union_range = range(-2, -2);


sub debug
{
	warn @_;
}
sub error
{
	warn @_;
}


sub hn2dotdec
{
	return join '.', unpack 'C4', pack 'N', $_[0];
}
sub dotdec2hn
{
	return unpack 'N', pack 'C4', split /\./, $_[0];
}

sub range2regex
{
	my $min = shift;
	my $max = shift;
	my $mask = shift;
	
	my $ddmin = hn2dotdec $min;
	my $ddmax = hn2dotdec $max;
	my @ddmin = split /\./, $ddmin;
	my @ddmax = split /\./, $ddmax;
	my @results;
	
	$indent .= '  ';
	debug "$indent$ddmin - $ddmax /$mask\n";
	
	if(not defined $mask)
	{
		if($min == $max)
		{
			push @results, quotemeta $ddmin . '$';
		}
		else
		{
			for my $octet (0..3)
			{
				if($ddmin[$octet] != $ddmax[$octet])
				{
					my $mask = ($octet+1) * 8;
					my $bound_low  = all {$ddmin[$_] == 0} $octet+1..3;
					my $bound_high = all {$ddmax[$_] == $octet_max} $octet+1..3;
					
					if($bound_low and $bound_high)
					{
						push @results, range2regex($min, $max, $mask);
					}
					else
					{
						my @ddcut1 = @ddmin;
						my @ddcut2 = @ddmax;
						for my $octet_right ($octet+1..3)
						{
							$ddcut1[$octet_right] = $octet_max;
							$ddcut2[$octet_right] = 0;
						}
						my $cut1 = dotdec2hn(join '.', @ddcut1);
						my $cut2 = dotdec2hn(join '.', @ddcut2);
						
						if($bound_low)
						{
							push @results, range2regex($min, $cut2-1, $mask);
							push @results, range2regex($cut2, $max, undef);
						}
						elsif($bound_high)
						{
							push @results, range2regex($min, $cut1, undef);
							push @results, range2regex($cut1+1, $max, $mask);
						}
						else
						{
							push @results, range2regex($min, $cut1, undef);
							if($cut1 < $cut2-1)
							{
								push @results, range2regex($cut1+1, $cut2-1, $mask);
							}
							push @results, range2regex($cut2, $max, undef);
						}
					}
					
					last;
				}
			}
		}
	}
	else
	{
		my @octets;
		
		for my $octet (0..3)
		{
			if($ddmin[$octet] == $ddmax[$octet])
			{
				push @octets, $ddmin[$octet];
			}
			elsif(int(($mask-1)/8) == $octet-1)
			{
				push @octets, '';
				last;
			}
			else
			{
				push @octets, range($ddmin[$octet], $ddmax[$octet])->regex;
			}
		}
		
		unshift @results, join('\.', @octets) . ($octets[-1] eq '' ? '' : '$');
	}
	
	$indent = ' ' x (length($indent)-2);
	return @results;
}


while(<>)
{
	s/[\r\n]+$//;
	my $cidr = $_;
	my $min;
	my $max;
	my $mask;
	
	if($cidr =~ /^($rr0_255\.$rr0_255\.$rr0_255\.$rr0_255) ($rr0_255\.$rr0_255\.$rr0_255\.$rr0_255)$/)
	{
		my ($minip, $maxip) = ($1, $2);
		$min = dotdec2hn($minip);
		$max = dotdec2hn($maxip);
	}
	elsif($cidr =~ /^($rr0_255\.$rr0_255\.$rr0_255\.$rr0_255)\/($rr0_32)$/)
	{
		my $netip;
		($netip, $mask) = ($1, $2);
		
		$min = dotdec2hn($netip) & (0xFFFFFFFF << ($af_length - $mask));
		$max = $min + 2**($af_length - $mask) - 1;
		#my $bmin = reverse pack('I', $min);
		#my $bmax = reverse pack('I', $max);
	}
	else
	{
		error "neither a CIDR/mask nor a pair of IPs: '$cidr'\n";
		next;
	}
	
	$union_range = $union_range->union(range($min, $max));
	
	debug "# $cidr\n";
	my @regexps = range2regex($min, $max, $mask);
	print map {"^$_\n"} @regexps;
}


print STDERR "United ranges:\n";
print "\n";
$ranges_str = substr $union_range, 3;
for my $range (split /,/, $ranges_str)
{
	debug "# $range\n";
	my $min;
	my $max;
	($min, $max) = $range =~ /(\d+)\.\.(\d+)/ or $min = $max = $range;
	my $mask = undef; #TODO
	my @regexps = range2regex($min, $max, $mask);
	print map {"^$_\n"} @regexps;
	
	for my $regex (@regexps)
	{
		my @octets = split /\\\./, $regex;
		$RH->{$octets[0]}->{$octets[1]}->{$octets[2]}->{$octets[3]} = 1;
	}
}


for my $o1 (keys $RH)
{
	print "|-- $o1\n";
	for my $o2 (keys $RH->{$o1})
	{
		print "    |-- $o2\n";
		for my $o3 (keys $RH->{$o1}->{$o2})
		{
			print "        |-- $o3\n";
			for my $o4 (keys $RH->{$o1}->{$o2}->{$o3})
			{
				print "            |-- $o4\n";
			}
		}
	}
}
