use strict;
use URI;
use Date::Simple ('date', 'today');
use Date::Calc qw/Delta_Days/;
use LWP::Simple;
use HTML::Restrict;
use open qw/:std :utf8/;
use Term::ProgressBar;
use feature qw(say);
use threads;
$|=1;

my $hash = ();
my $hr = HTML::Restrict->new();
my $date 	= date('2015-01-01');
my $end 	= date('2015-12-31');

my $duration = Delta_Days( ($date->year,$date->month,$date->day), ($end->year,$end->month,$end->day));

say "Hello";
say "Downloading article structure from $date till $end";
my $name = "Article structure";
my $progress = Term::ProgressBar->new(
   { name  => $name,
     count => $duration,
     term_width => 80,
     remove => 1
    });
my $done = 0;

while($date < $end) {
	my $format_date = sprintf("%4d%02d%02d",$date->year,$date->month,$date->day);
	my $url = "http://www.hln.be/hln/nl/1/archief/integration/nmc/frameset/archive/archiveDay.dhtml?archiveDay=$format_date";
	$progress->update (++$done);
	my $content = get $url;
	$content =~ /Het\ archief\ is\ niet\ beschikbaar\ voor/g && die "$format_date doesn't work";

	my @categories = ($content =~ m/<h2>\n<a\ name=\"(.*)\"/g);
	my @dls = ($content =~ m/<dl>[\s\S]*?<\/dl>/g);
	my $i = 0;
	foreach my $category (@categories) {
		my @articles = ($dls[$i++] =~ m/\<dd\>\n<a\ href\=\"(.*)\"\>.*\<\/a\>/g);
		foreach my $article (@articles) {
			my $subcategory = ($article =~ m/http:\/\/www.hln.be\/hln\/nl\/(\d)+?\/(.*?)\/article/g)[1];
			#say "$category\t->\t$subcategory\t$article";
			push @{$hash->{$category}->{$subcategory}}, $article;
		}
	}
	$date++;
}

say "Processing articles...";
my $folder = "hln_output";
mkdir($folder);
my $thread_limit = 200;
foreach my $category (keys %{$hash}) {
	say "cat: $category";
	mkdir($folder."/".$category);	
    foreach my $subcategory (keys %{$hash->{$category}}) {
    	say "sub: $subcategory";
    	my $name = "Downloading $category/$subcategory";
    	my $progress = Term::ProgressBar->new(
		   	{ 
		   		name  => $name,
		     	count => scalar @{$hash->{$category}->{$subcategory}},
		     	term_width => 80,
		     	remove => 1
		    }
		);
    	mkdir($folder."/".$category."/".$subcategory);
		my $done = 0;
		foreach my $article_url (@{$hash->{$category}->{$subcategory}}) {
			$progress->update (++$done);
			my $thread = threads->create( \&process_article, $article_url , $category, $subcategory);
			my @threadlist = threads->list(threads::running);
			my $num_threads = $#threadlist;
			while($num_threads >= $thread_limit)
	     	{
				sleep(10);
				@threadlist = threads->list(threads::running);
				$num_threads = $#threadlist;
	    	}
		}
	}
}

sleep 1 while threads->list(threads::running) > 0;

sub process_article {
	my $article_url = shift;
	my $category = shift;
	my $subcategory = shift;
	my $article = get $article_url;
	my $filename = ($article_url =~ m/([^\/]+)\.dhtml$/g)[0];
	my $body = ($article =~ m/<div itemprop="body">([\s\S]*?)<div id="brandLikeContainer">/g)[0];
	my @output = ($body =~ m/<p.*?>([\s\S]*?)<\/p>/g);
	my $text = join("\n", @output);
	open(my $fh, '>', "./$folder/$category/$subcategory/$filename.txt") or die "Could not open file '$folder/$category/$subcategory/$filename' $!";
	my $processed = $hr->process($text);
	#$processed =~ s/\R//g;
	print $fh $processed;
	close $fh;
	threads->detach();
}