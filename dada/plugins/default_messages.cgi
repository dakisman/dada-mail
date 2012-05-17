#!/usr/bin/perl -w
package default_messages;
use strict;

# make sure the DADA lib is in the lib paths!
use lib qw(../ ../DADA/perllib);

# use some of those Modules
use DADA::Config 5.0.0;
use DADA::Template::HTML;
use DADA::App::Guts;
use DADA::MailingList::Settings;

# we need this for cookies things
use CGI;
my $q = new CGI;
$q->charset($DADA::Config::HTML_CHARSET);
$q = decode_cgi_obj($q);
use CGI::Carp qw(fatalsToBrowser);
use Carp qw(croak carp); 

use Fcntl qw(
	LOCK_SH
	O_RDONLY
	O_CREAT
	LOCK_EX
);


my $admin_list; 
my $root_login; 
my $list; 
my $pt_fn; 
my $html_fn; 

run()
  unless caller();

sub _init { 
	( $admin_list, $root_login ) = check_list_security(
        -cgi_obj  => $q,
        -Function => 'default_messages'
    );

	$list = $admin_list;
	$pt_fn = $DADA::Config::TEMPLATES . '/' . 'default_plaintext_message_content' . '-' . $list . '.txt';
	$html_fn = $DADA::Config::TEMPLATES . '/' . 'default_html_message_content' . '-' . $list . '.html';
	
}

sub run {

	_init(); 

	my $flavor = $q->param('flavor') || 'cgi_default';

	my %Mode = (
		'cgi_default'                => \&cgi_default,
		'save_params'                => \&save_params, 
		'view_file'                  => \&view_file, 
	);

	if ( exists( $Mode{$flavor} ) ) {
		$Mode{$flavor}->();    #call the correct subroutine
	}
	else {
		&cgi_default;
	}
}

sub cgi_default_tmpl {

return q{ 
	
	
	<!-- tmpl_set name="title" value="Default Messages" -->
	<!-- tmpl_set name="load_modalbox" value="1" -->
	
	<form action="<!-- tmpl_var Plugin_URL -->" method="post" method="post" accept-charset="<!-- tmpl_var HTML_CHARSET -->">
	<input type="hidden" name="flavor" value="save_params" />
	
	<fieldset> 
		<legend>PlainText Message</legend>
		
		<table border="0" cellpadding="5" width="100%"> 
			<tr> 
			<td>
			 <p>
			  <input type="radio" id="default_plaintext_message_content_src_default" name="default_plaintext_message_content_src" value="default" <!-- tmpl_if expr="(list_settings.default_plaintext_message_content_src eq 'default')" -->checked="checked"<!-- /tmpl_if --> />
			<label for="default_plaintext_message_content_src_default">Use the following PlainText as content: </label><br /> 
			
			<textarea cols="80" rows="30" name="default_plaintext_message_content_data"><!-- tmpl_var default_plaintext_message_content_data escape="HTML" --></textarea>
			 </p>
			</td> 
			
			
			</tr>
			<tr>
				<td>
				 <p>
				  <input type="radio" id="default_plaintext_message_content_src_url_or_path" name="default_plaintext_message_content_src" value="url_or_path" <!-- tmpl_if expr="(list_settings.default_plaintext_message_content_src eq 'url_or_path')" -->checked="checked"<!-- /tmpl_if --> />
				<label for="default_plaintext_message_content_src_url_or_path">Grab content from this webpage address (URL), or Server Path: </label>
				<!-- tmpl_if plaintext_message_source_isa_url --> 
					<a href="<!-- tmpl_var list_settings.default_plaintext_message_content_src_url_or_path -->" target="_blank">
						(View Current URL)
					</a> 
				<!-- /tmpl_if --> 
				<!-- tmpl_if plaintext_message_source_isa_file --> 
				<a href="<!-- tmpl_var Plugin_URL -->?flavor=view_file;fn=default_plaintext_message_content_src_url_or_path" title="PlainText Message" onclick="Modalbox.show(this.href, {title: this.title, width: 640, height:480}); return false;">
					(View File...)
				</a>
				<!-- /tmpl_if -->
				<!-- tmpl_if problems_fetching_plaintext_url -->
					<span class="error">Can't fetch URL!</span>
				<!-- /tmpl_if -->  
				<!-- tmpl_if problems_opening_plaintext_file --> 
					<span class="error">Can't open file!</span>
				<!-- /tmpl_if --> 
				<br /> 
				
				<input type="text" class="full"  name="default_plaintext_message_content_src_url_or_path" value="<!-- tmpl_var list_settings.default_plaintext_message_content_src_url_or_path escape="HTML" -->"/>
				 </p>
				</td> 
			</tr> 
		</table> 
		
	</fieldset> 
	
	<div class="buttonfloat">
	 <input type="submit" class="processing" name="process" value="Save" />
	</div>
	<div class="floatclear"></div>
	
	
	

	</form> 


};

}

sub cgi_default { 
	
	my $data = cgi_default_tmpl(); 
    require DADA::Template::Widgets;
	require DADA::MailingList::Settings; 
	my $ls = DADA::MailingList::Settings->new({-list => $list}); 	
	
	
	my $default_plaintext_message_content_data = ''; 
	if(-e $pt_fn){ 
		$default_plaintext_message_content_data = slurp($pt_fn); 
	} 
	my $default_html_message_content_data = ''; 
	if(-e $html_fn){ 
		$default_html_message_content_data = slurp($html_fn); 
	}


	my $plaintext_message_source_isa_url  = isa_url($ls->param('default_plaintext_message_content_src_url_or_path'));
	
	my $plaintext_message_source_isa_file = 0; 
	if(length($ls->param('default_plaintext_message_content_src_url_or_path')) > 0 && $plaintext_message_source_isa_url != 1){ 
		$plaintext_message_source_isa_file = 1;
	}

	my $problems_fetching_plaintext_url = 0; 
	my $problems_opening_plaintext_file = 0;
	if(length($ls->param('default_plaintext_message_content_src_url_or_path')) > 0){ 
		if($plaintext_message_source_isa_url == 1){ 
			
			if(grab_url($ls->param('default_plaintext_message_content_src_url_or_path'))){ 
		
			}
			else { 
				$problems_fetching_plaintext_url = 1; 
			}
		}
		elsif($plaintext_message_source_isa_file == 1) { 
			if(-e $ls->param('default_plaintext_message_content_src_url_or_path')){ 
				# ... 				
			}
			else { 
				$problems_opening_plaintext_file = 1; 
			}
		}
	}
	
     my $scrn = DADA::Template::Widgets::wrap_screen(
         {
             -data           => \$data,
             -with           => 'admin',
			 -expr           => 1, 
             -wrapper_params => {
                 -Root_Login => $root_login,
                 -List       => $list,
             },
             -vars => {
				default_plaintext_message_content_data => $default_plaintext_message_content_data, 
				default_html_message_content_data      => $default_html_message_content_data, 
				Plugin_URL => $q->url, 
				plaintext_message_source_isa_url       => $plaintext_message_source_isa_url,
				plaintext_message_source_isa_file      => $plaintext_message_source_isa_file, 
				problems_fetching_plaintext_url        => $problems_fetching_plaintext_url, 
			    problems_opening_plaintext_file        => $problems_opening_plaintext_file, 
			},
			-list_settings_vars_param => { 
				-list                 => $list,
				-dot_it               => 1,
			},

         }
     );
     e_print($scrn);
}

sub save_params { 
	
	my $default_plaintext_message_content_data = $q->param('default_plaintext_message_content_data'); 
	my $default_html_message_content_data      = $q->param('default_html_message_content_data'); 
	my $pt_return   = 1; 
	my $html_return = 1; 
	if(length($default_plaintext_message_content_data) > 0){ 
		$pt_return = save_file($pt_fn, $default_plaintext_message_content_data); 
	}
	if(length($default_html_message_content_data) > 0){ 
		$html_return = save_file($html_fn, $default_html_message_content_data); 
	}
	
	require DADA::MailingList::Settings; 
	my $ls = DADA::MailingList::Settings->new({-list => $list}); 	
	$ls->save_w_params(
		{
			-associate => $q, 
			-settings  => { 
				default_plaintext_message_content_src             => undef, 
				default_plaintext_message_content_src_url_or_path => undef, 
				default_html_message_content_src                  => undef, 
				default_html_message_content_src_url_or_path      => undef, 
			}
		}
	);
	print $q->redirect($q->url . '?done=1;pt_return=' . $pt_return . ';html_return=' . $html_return); 
}

sub save_file { 
	my $fn = shift; 
	my $data = shift; 
	$fn = make_safer($fn);
	eval { 
		open(TEMPLATE, '>:encoding(' . $DADA::Config::HTML_CHARSET . ')', $fn) or 
			croak "$DADA::Config::PROGRAM_NAME $DADA::Config::VER Error: can't write file $fn': $!"; 
		flock(TEMPLATE, LOCK_EX) or 
			croak "$DADA::Config::PROGRAM_NAME $DADA::Config::VER Error: can't lock to write new file at '$fn': $!" ; 
		print TEMPLATE $data;
		close(TEMPLATE); 
	    chmod($DADA::Config::FILE_CHMOD , $fn); 
	};
	
	if($@){ 
		return undef; 
	}
	else { 
		return 1; 
	}

}

sub view_file { 
	my $fn = xss_filter($q->param('fn')); 
	my $data = undef; 
	print $q->header(); 
	
	require DADA::MailingList::Settings; 
	my $ls = DADA::MailingList::Settings->new({-list => $list}); 	
	if($fn eq 'default_plaintext_message_content_src_url_or_path') { 
		$data = slurp($ls->param('default_plaintext_message_content_src_url_or_path'));
		e_print($q->pre(convert_to_html_entities($data))); 
	}
	else { 
		croak('sorry I cannot show, ' . $fn);
	}
	
}
