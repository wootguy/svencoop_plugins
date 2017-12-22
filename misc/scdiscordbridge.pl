#!/usr/bin/env perl

# to use with scripts/plugins/DiscordStatus.as

use 5.16.0;

use utf8; 
use strict; 
use warnings; 

use File::Tail;
use LWP::UserAgent;

### config

my $tailfile = "$ENV{'HOME'}/sc5/svencoop/scripts/plugins/store/discordbridge.txt";
my $webhookurl_serverstatus = ''; 
my $webhookurl_general = '';

my $maps = {
   'hl_c01_a1' => '<:hl:369091257999294464> Half-Life',
   'of1a1' => '<:of:370226020982325250> Opposing Force',
   'ba_security1' => '<:bs:370225849426771979> Blue Shift',
   'escape_series_1a' => '<:sc:370225689514737665> Escape Series: Part 1',
   'escape_series_2a' => '<:sc:370225689514737665> Escape Series: Part 2',
   'escape_series_3a' => '<:sc:370225689514737665> Escape Series: Part 3',
   'etc' => '<:sc:370225689514737665> Earthquake Test Center',
   'etc2_1' => '<:sc:370225689514737665> Earthquake Test Center 2',
   'mistake_coop_a' => '<:sc:370225689514737665> Mistake Co-op',
   'po_c1m1' => '<:sc:370225689514737665> Poke 646',
   'po_c1m1' => '<:sc:370225689514737665> Poke 646: Vendetta',
   'rl02' => '<:sc:370225689514737665> Residual Life',
   'th_ep1_00' => '<:th:372377213779312640> They Hunger: Episode 1',
   'th_ep2_00' => '<:th:372377213779312640> They Hunger: Episode 2',
   'th_ep3_00' => '<:th:372377213779312640> They Hunger: Episode 3',
   'road_to_shinnen' => '<:twlz:370619463038664705> Oh no, Road to Shinnen',
   'sc_tl_build_puzzle_fft_final' => '<:lul:370224421933285386> Build Puzzle'
};

###

if (-e $tailfile) {
   my $tail = File::Tail->new( name => $tailfile, reset_tail => 0, maxbuf => 2048, maxinterval => 5 );

   while( defined( my $line = $tail->read ) ) {
      chomp( $line );
      next if( $line =~ /^$/ );

      say $line;

      my @data = split( ' ', $line );

      my $r = HTTP::Request->new( 'POST', $webhookurl_serverstatus );
      $r->content_type( 'application/json' );
      $r->content( "{\"content\":\"map: **$data[0]** players: **$data[1]**\"}" );

      my $ua = LWP::UserAgent->new;
      $ua->agent('Mozilla/5.0');
      $ua->request( $r );

      if( exists( $$maps{$data[0]} ) ) {
        my $r2 = HTTP::Request->new( 'POST', $webhookurl_general );
        $r2->content_type( 'application/json' );
        $r2->content( "{\"content\":\" **$$maps{$data[0]}** campaign has started with **$data[1]** players!\"}" );

        my $ua2 = LWP::UserAgent->new;
        $ua2->agent('Mozilla/5.0');
        $ua2->request( $r2 );
      }
   }
}
else {
   exit 1;
}
