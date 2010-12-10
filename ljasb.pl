#!/usr/bin/env perl
# 02 Oct 2009 
# gark_87.lj.ru <Arkady Galyash>
# under GPLv2 or later
# 
# For matmex LJ community - automate new members approval

use strict;
use warnings;

# for mail use IMAP with SSL
# gmail.com, for example, use IMAP with SSL
use Net::IMAP::Simple::SSL;
use Email::Simple;

# for LJ posting
use LWP::UserAgent;
use HTTP::Request::Common qw(POST GET);

use constant LJ        => 'http://www.livejournal.com/';
use constant INBOX     => 'inbox/compose.bml';
use constant PENDING   => 'community/pending.bml?authas=';

#
# return answers from lj users
#
sub read_mail($$)
{
  my ($imap, $config) = @_;
  my %answers  = ();

  # test that directory with comments-answers exists
  my $dir = $config->Mail::answers;
  my $nm = $imap->select($dir);
  defined $nm or 
    die "No folder `$dir' on mail account. Check config and mail account.\n";

  # check answers
  foreach my $i (1..$nm)
  {
    my $es = Email::Simple->new(join '', @{ $imap->top($i) } );
    next unless ($es->header('From') =~
       m/"([^ ]+) - LJ Comment" <lj_notify\@livejournal.com>/);
     
    my $user = $1;
    my ($question, $answer) = $config->QA($user);
    # get the message, returned as a reference to an array of lines
    my $reply = '';

    # cut off needed information from mail to $reply variable
    foreach my $_ (@{ $imap->get($i) })
    {
      # start from this line
      if (/Their reply was:/../From here, you can:/) 
      {
        s/=[\r\n]+$//g;
        $reply .= $_;
      }
    }

    # delete all html tags. leave only text
    $reply =~ s/<[^>]+>//g; 

    # Presumption of "noscere"
    $answers{$user} = 0;
    foreach my $line (split(/[\n\r]+/, $reply))
    {
      $answers{$user} |= ($line =~ m/^[ \t]*$answer[ \t]*$/);
    }
  }
  return %answers;
}

#
# do LJ login for cookies only
#
sub LJ_login($)
{
  my ($config) = @_;
  # let 'browser' have cookies 
  my $browser = LWP::UserAgent->new;
  $browser->cookie_jar( {} );

  $browser->request(
     POST LJ.'login.bml',
     [
       user     => $config->LJ::user,
       password => $config->LJ::password
     ]
  );
  return $browser;
}

sub LJ_approve($$%)
{
  my ($browser, $config, %answers) = @_;
  my $req = GET LJ.PENDING.$config->LJ::community;
  my $res = $browser->request($req);
  my $page = $res->content;
  return ((), ()) if ($page =~ 
      m/There are no pending membership requests for this community/);

  my ($auth) = ($page =~ m/name="lj_form_auth" value="([^"]+)"/);
  my ($ids)  = ($page =~ m/name="ids" value="([0-9,]+)"/);

  (defined $auth and defined $ids) or
       die "Cannot get into community\n";

  my $reject_opts ={ 
      lj_form_auth => $auth,
      reject       => 'Reject membership',
      ids          => $ids
  };

  my $approve_opts = {
      lj_form_auth => $auth,
      approve      => 'Approve membership',
      ids          => $ids
  };

  my %questions = ();
  my %users = ($page =~ m/<input type='checkbox' checked='checked' name="(pending_[0-9]+).*lj:user='([^']*)'/g);
  foreach my $key (keys %users)
  {
    my $user = $users{$key};
    my $res = $answers{$user};
    $questions{$user} = ($config->QA)[0] unless defined $res; 
    (($res)?$approve_opts:$reject_opts)->{$key} = 'on' if defined $res;
  }

  my $reject_result;
  my @to_delete;
  if (keys %{$approve_opts} > 3)
  {
    my @users = grep {$answers{$_}} (keys %answers);
    print "Trying to approve users(@users) - ";
    my $page = $browser->request(POST LJ.PENDING.$config->LJ::community, $approve_opts)->content;
    my $result =($page =~ m/You have added ([0-9]+) persons? to this community./
	and $1+3 == keys %{$approve_opts});
    print STDOUT($result?'OK':'FAILED')."\n";
    push @to_delete, @users if $result;
  }
  if (keys %{$reject_opts} > 3)
  {
    my @users = grep {not $answers{$_}} (keys %answers);
    print "Trying to reject users(@users) - ";
    my $page = $browser->request(POST LJ.PENDING.$config->LJ::community, $reject_opts)->content;
    my $result = ($page =~ 
	m/You have rejected ([0-9]+) requests? to join this community./
	and $1+3 == keys %{$reject_opts});
    print STDOUT ($result?'OK':'FAILED')."\n";
    push @to_delete, @users if $result;
  }

  return (\@to_delete, \%questions);
}

#
# send private messages with questions to LJ users
#
sub send_LJ_pm($$%)
{
  my ($browser, $config, %pms) = @_;

  # get lj_form_auth field
  my $page = $browser->request(POST LJ.INBOX)->content;
  my ($auth) = $page =~ m/name="lj_form_auth" value="([^"]+)"/;
  die "Cannot get into inbox.\n" if not defined $auth;

  foreach my $user (keys %pms)
  {
    my $question = $pms{$user};

    my $page = $browser->request(
      POST LJ.INBOX, 
      [
	 msg_subject  => $question,
	 msg_body     => $config->body,
	 msg_to       => $user,
	 lj_form_auth => $auth,
	 mode         => 'send'
       ]
    )->content;
    print "send question to $user - ".
    ((-1 == index($page, 'There was an error processing your request:'))?
      'OK': 'FAILED')."\n";
  }
}

sub delete_mail($$@)
{
  my ($imap, $config, @users) = @_;
  
  # test that directory with comments-answers exists
  my $nm = $imap->select($config->Mail::answers);
  defined $nm or 
    die "No folder `answers' on mail account. Check config and mail account.\n";

  # check answers
  foreach my $i (1..$nm)
  {
    my $es = Email::Simple->new(join '', @{ $imap->top($i) } );
    next unless ($es->header('From') =~
       m/"([^ ]+) - LJ Comment" <lj_notify\@livejournal.com>/);

    $imap->delete($i) if grep {$1 eq $_} @users;
  }
}

# load config
require "config.pl";

my @configs = ();
foreach my $symname (sort keys %LJASB::) {
  $symname =~ s/::$//;
  push @configs, "LJASB::$symname";
}
foreach my $config (@configs) {
  print "start processing community `$config'\n";
  my $imap = Net::IMAP::Simple::SSL->new($config->Mail::server) or 
       die "Unable to connect to mail\n";
  defined $imap->login($config->Mail::user, $config->Mail::password) or
      die "Unable to login to mail\n";
  my %approves = read_mail($imap, $config);
  my $browser = LJ_login($config);
  my ($to_delete, $questions) = LJ_approve($browser, $config, %approves);
  send_LJ_pm($browser, $config, %{ $questions });
  delete_mail($imap, $config, @{ $to_delete });
  $imap->quit;
}

