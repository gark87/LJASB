{
  package LJASB::MatMex;
  sub Mail::user         { die "change Mail::user" }       # mail account 
  sub Mail::password     { die "change Mail::password" }   # mail password
  sub Mail::server       { die "change Mail::server" }     # mail server
  sub Mail::answers      { die "change Mail::answers" }    # mail folder with answers
  sub LJ::community      { die "change LJ::community" }    # LJ community name
  sub LJ::user           { die "change LJ::user" }         # LJ user-moderator
  sub LJ::password       { die "change LJ::password" }     # LJ moderator's password
  #
  # message that describes community policy 
  #
  sub body()
  {
    'You receive this message because you want to join matmex LJ community.'.
    ' For complete registration, please, answer the question'.
    ' in the subject of this message as comment to post'.
    ' http://mmmoderator.livejournal.com/763.html';
  }
  
  #
  #  generate Question and Answer for this %username%
  #
  sub QA($) 
  {
    my ($member) = @_;
    return ('d(2*x-x+100)/dx=?', '1');
  }
}
1;
