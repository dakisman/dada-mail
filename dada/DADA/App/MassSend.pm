package DADA::App::MassSend;

use lib qw(
  ../../
  ../../DADA/perllib
);

use DADA::Config qw(!:DEFAULT);
use DADA::App::Guts;
use DADA::Template::HTML;

use Carp qw(carp croak);

use strict;
use vars qw($AUTOLOAD);

my $t = $DADA::Config::DEBUG_TRACE->{DADA_App_MassSend};

my %allowed = ( test => 0, );

sub new {

    my $that = shift;
    my $class = ref($that) || $that;

    my $self = {
        _permitted => \%allowed,
        %allowed,
    };

    bless $self, $class;

    my %args = (@_);

    $self->_init( \%args );
    return $self;
}

sub AUTOLOAD {
    my $self = shift;
    my $type = ref($self)
      or croak "$self is not an object";

    my $name = $AUTOLOAD;
    $name =~ s/.*://;    #strip fully qualifies portion

    unless ( exists $self->{_permitted}->{$name} ) {
        croak "Can't access '$name' field in object of class $type";
    }
    if (@_) {
        return $self->{$name} = shift;
    }
    else {
        return $self->{$name};
    }
}

sub _init { }

sub send_email {

    my $self   = shift;
    my ($args) = @_;
    my $q      = $args->{-cgi_obj};
    my $list;
    my $root_login = $args->{-root_login};

    my $process            = xss_filter( strip( $q->param('process') ) );
    my $flavor             = xss_filter( strip( $q->param('flavor') ) );
    my $restore_from_draft = xss_filter( strip( $q->param('restore_from_draft') ) ) || 'true';
    my $test_sent          = xss_filter( strip( $q->param('test_sent') ) ) || 0;
    my $test_recipient     = xss_filter( strip( $q->param('test_recipient') ) );

    if ( !exists( $args->{-list} ) ) {
        croak "You must pass the -list parameter!";
    }
    else {
        $list = $args->{-list};
    }

    if ( !exists( $args->{-html_output} ) ) {
        $args->{-html_output} = 1;
    }

    require DADA::MailingList::Settings;

    my $ls = DADA::MailingList::Settings->new( { -list => $list } );
    my $li = $ls->get;

    require DADA::MailingList::Subscribers;
    my $lh = DADA::MailingList::Subscribers->new( { -list => $list } );

    my $fields = [];

    # Extra, special one...
    push( @$fields, { name => 'subscriber.email' } );
    for my $field ( @{ $lh->subscriber_fields( { -dotted => 1 } ) } ) {
        push( @$fields, { name => $field } );
    }

    my $undotted_fields = [];

    # Extra, special one...
    push( @$undotted_fields, { name => 'email', label => 'Email Address' } );
    require DADA::ProfileFieldsManager;
    my $pfm         = DADA::ProfileFieldsManager->new;
    my $fields_attr = $pfm->get_all_field_attributes;
    for my $undotted_field ( @{ $lh->subscriber_fields( { -dotted => 0 } ) } ) {
        push(
            @$undotted_fields,
            {
                name  => $undotted_field,
                label => $fields_attr->{$undotted_field}->{label}
            }
        );
    }

    if ( !$process ) {
        my ( $num_list_mailouts, $num_total_mailouts, $active_mailouts, $mailout_will_be_queued ) =
          $self->mass_mailout_info($list);

        my $draft_id = undef;
			
        require DADA::MailingList::MessageDrafts;
        my $d = DADA::MailingList::MessageDrafts->new( { -list => $list } );
        if ( $d->enabled ) {

            if (   $restore_from_draft ne 'true'
                && $d->has_draft( { -screen => 'send_email' } ) )
            {
                $draft_id = undef;
            }
            elsif ($restore_from_draft eq 'true'
                && $d->has_draft( { -screen => 'send_email' } ) )
            {
                if ( defined( $q->param('draft_id') ) ) {
                    $draft_id = $q->param('draft_id');
                }
                else {
                    $draft_id = $d->latest_draft_id( { -screen => 'send_email' } );
                }
            }
        }

        require DADA::Template::Widgets;
        my %wysiwyg_vars = DADA::Template::Widgets::make_wysiwyg_vars($list);

        my $scrn = DADA::Template::Widgets::wrap_screen(
            {
                -screen         => 'send_email_screen.tmpl',
                -with           => 'admin',
                -expr           => 1,
                -wrapper_params => {
                    -Root_Login => $root_login,
                    -List       => $list,
                },
                -vars => {
                    screen                     => 'send_email',
                    flavor                     => $flavor,
                    draft_id                   => $draft_id,
                    draft_enabled              => $d->enabled,
                    test_sent                  => $test_sent,
                    test_recipient             => $test_recipient,
                    priority_popup_menu        => DADA::Template::Widgets::priority_popup_menu($li),
                    type                       => 'list',
                    fields                     => $fields,
                    undotted_fields            => $undotted_fields,
                    can_have_subscriber_fields => $lh->can_have_subscriber_fields,

                    # I don't really have this right now...
                    MAILOUT_AT_ONCE_LIMIT  => $DADA::Config::MAILOUT_AT_ONCE_LIMIT,
                    kcfinder_url           => $DADA::Config::FILE_BROWSER_OPTIONS->{kcfinder}->{url},
                    kcfinder_upload_dir    => $DADA::Config::FILE_BROWSER_OPTIONS->{kcfinder}->{upload_dir},
                    kcfinder_upload_url    => $DADA::Config::FILE_BROWSER_OPTIONS->{kcfinder}->{upload_url},
                    mailout_will_be_queued => $mailout_will_be_queued,
                    num_list_mailouts      => $num_list_mailouts,
                    num_total_mailouts     => $num_total_mailouts,
                    active_mailouts        => $active_mailouts,
                    global_list_sending_checkbox_widget =>
                      DADA::Template::Widgets::global_list_sending_checkbox_widget($list),
                    plaintext_message_body_content       => $ls->plaintext_message_body_content,
                    html_message_body_content            => $ls->html_message_body_content,
                    html_message_body_content_js_escaped => js_enc( $ls->html_message_body_content ),
                    %wysiwyg_vars,
                },
                -list_settings_vars       => $ls->params,
                -list_settings_vars_param => { -dot_it => 1, },
            }
        );

        if ( $restore_from_draft eq 'true' ) {
            $scrn = $self->fill_in_draft_msg(
                {
                    -list     => $list,
                    -screen   => 'send_email',
                    -str      => $scrn,
                    -draft_id => $draft_id,

                }
            );
        }
        if ( $args->{-html_output} == 1 ) {
            e_print($scrn);
        }

    }
    elsif ( $process eq 'save_as_draft' ) {
        $self->save_as_draft( { -cgi_obj => $q, -list => $list } );
    }
    else {

        my $draft_id = $q->param('draft_id');

        require DADA::App::FormatMessages;
        my $fm = DADA::App::FormatMessages->new( -List => $list );
        $fm->mass_mailing(1);

        # DEV: Headers.  Ugh, remember this is in, "Send a Webpage" as well.
        my %headers = ();
        for my $h (
            qw(
            Reply-To
            Errors-To
            Return-Path
            X-Priority
            Subject
            )
          )
        {
            if ( defined( $q->param($h) ) ) {
                $headers{$h} = strip( $q->param($h) );
            }
        }

        #/Headers

        # Are we archiving this message?
        if ( defined( $q->param('local_archive_options_present') ) ) {
            if ( $q->param('local_archive_options_present') == 1 ) {
                if ( $q->param('archive_message') != 1 ) {
                    $q->param( -name => 'archive_message', -value => 0 );
                }
            }
        }

        my $archive_m = $li->{archive_messages} || 0;
        if (   $q->param('archive_message') == 1
            || $q->param('archive_message') == 0 )
        {
            $archive_m = $q->param('archive_message');
        }

        # /Are we archiving this message?

        require MIME::Lite;
        $MIME::Lite::PARANOID = $DADA::Config::MIME_PARANOID;

        my $email_format = $q->param('email_format');
        my $attachment   = $q->param('attachment');

        my $text_message_body = $q->param('text_message_body') || undef;
        my $html_message_body = $q->param('html_message_body') || undef;

        ( $text_message_body, $html_message_body ) =
          DADA::App::FormatMessages::pre_process_msg_strings( $text_message_body, $html_message_body );
        my $msg;

        if ( $html_message_body && $text_message_body ) {

            $text_message_body = safely_encode($text_message_body);
            $html_message_body = safely_encode($html_message_body);

            return undef
              if redirect_tag_check( $text_message_body, $list, $root_login ) eq undef;
            return undef
              if redirect_tag_check( $html_message_body, $list, $root_login ) eq undef;

            $msg = MIME::Lite->new(
                Type      => 'multipart/alternative',
                Datestamp => 0,
                %headers,
            );
            $msg->attr( 'content-type.charset' => $li->{charset_value} );

            my $pt_part = MIME::Lite->new(
                Type     => 'text/plain',
                Data     => $text_message_body,
                Encoding => $li->{plaintext_encoding},
            );
            $pt_part->attr( 'content-type.charset' => $li->{charset_value} );

            $msg->attach($pt_part);
            my $html_part = MIME::Lite->new(
                Type     => 'text/html',
                Data     => $html_message_body,
                Encoding => $li->{html_encoding},
            );
            $html_part->attr( 'content-type.charset' => $li->{charset_value} );

            $msg->attach($html_part);

        }
        elsif ($html_message_body) {

            $html_message_body = safely_encode($html_message_body);

            return undef
              if redirect_tag_check( $html_message_body, $list, $root_login ) eq undef;

            $msg = MIME::Lite->new(
                Type      => 'text/html',
                Data      => $html_message_body,
                Encoding  => $li->{html_encoding},
                Datestamp => 0,
                %headers
            );
            $msg->attr( 'content-type.charset' => $li->{charset_value} );
        }
        elsif ($text_message_body) {

            $text_message_body = safely_encode($text_message_body);
            return undef
              if redirect_tag_check( $text_message_body, $list, $root_login ) eq undef;
            $msg = MIME::Lite->new(
                Type      => 'TEXT',
                Data      => $text_message_body,
                Encoding  => $li->{plaintext_encoding},
                Datestamp => 0,
                %headers,
            );
            $msg->attr( 'content-type.charset' => $li->{charset_value} );
        }
        else {
            report_mass_mail_errors( "There's no text in either the PlainText or HTML version of your email message!",
                $list, $root_login );
            return;
        }

        my @attachments = $self->has_attachments( { -cgi_obj => $q } );

        my @compl_att = ();

        if (@attachments) {
            my @compl_att = ();

            for (@attachments) {

                #carp '$_ ' . $_;

                my ($msg_att) = $self->make_attachment( { -name => $_, -cgi_obj => $q } );
                push( @compl_att, $msg_att )
                  if $msg_att;
            }

            if ( $compl_att[0] ) {
                my $mpm_msg = MIME::Lite->new(
                    Type      => 'multipart/mixed',
                    Datestamp => 0,
                );
                $mpm_msg->attach($msg);
                for (@compl_att) {
                    $mpm_msg->attach($_);
                }
                $msg = $mpm_msg;
            }
        }

        my $msg_as_string = ( defined($msg) ) ? $msg->as_string : undef;
        $msg_as_string = safely_decode($msg_as_string);

        $fm->Subject( $headers{Subject} );

        my ( $final_header, $final_body );
        eval { ( $final_header, $final_body ) = $fm->format_headers_and_body( -msg => $msg_as_string ); };
        if ($@) {
            report_mass_mail_errors( $@, $list, $root_login );
            return;
        }
        require DADA::Mail::Send;

        my $mh = DADA::Mail::Send->new(
            {
                -list   => $list,
                -ls_obj => $ls,
            }
        );

        unless ( $mh->isa('DADA::Mail::Send') ) {
            croak "DADA::Mail::Send object wasn't created correctly?";
        }

        $mh->test( $self->test );

        my %mailing = ( $mh->return_headers($final_header), Body => $final_body, );

        ###### Blah blah blah, parital listing
        my $partial_sending = {};
        for my $field (@$undotted_fields) {
            if ( $q->param( 'field_comparison_type_' . $field->{name} ) eq 'equal_to' ) {
                $partial_sending->{ $field->{name} } = { equal_to => $q->param( 'field_value_' . $field->{name} ) };
            }
            elsif ( $q->param( 'field_comparison_type_' . $field->{name} ) eq 'like' ) {
                $partial_sending->{ $field->{name} } = { like => $q->param( 'field_value_' . $field->{name} ) };
            }
            elsif ( $q->param( 'field_comparison_type_' . $field->{name} ) eq 'not_equal_to' ) {
                $partial_sending->{ $field->{name} } = { not_equal_to => $q->param( 'field_value_' . $field->{name} ) };
            }
            elsif ( $q->param( 'field_comparison_type_' . $field->{name} ) eq 'not_like' ) {
                $partial_sending->{ $field->{name} } = { not_like => $q->param( 'field_value_' . $field->{name} ) };
            }

        }

        ######/ Blah blah blah, parital listing

        my $message_id;
        my $og_test_recipient = '';
        if ( $q->param('archive_no_send') != 1 ) {

            my @alternative_list = ();
            @alternative_list = $q->param('alternative_list');
            $og_test_recipient = $q->param('test_recipient') || '';
            $mh->mass_test_recipient($og_test_recipient);
            $test_recipient = $mh->mass_test_recipient;

            my $multi_list_send_no_dupes = $q->param('multi_list_send_no_dupes')
              || 0;

            $message_id = $mh->mass_send(
                {
                    -msg             => {%mailing},
                    -partial_sending => $partial_sending,
                    -multi_list_send => {
                        -lists    => [@alternative_list],
                        -no_dupes => $multi_list_send_no_dupes,
                    },
                    -also_send_to => [@alternative_list],
                    ( $process =~ m/test/i )
                    ? (
                        -mass_test      => 1,
                        -test_recipient => $og_test_recipient,
                      )
                    : ( -mass_test => 0, )

                }
            );
        }
        else {

            # This is currently similar code as what's in the DADA::Mail::Send::_mail_general_headers method...

            my $msg_id = DADA::App::Guts::message_id();

            if ( $q->param('back_date') == 1 ) {
                $msg_id = $self->backdated_msg_id( { -cgi_obj => $q } );
            }

            %mailing = $mh->clean_headers(%mailing);

            %mailing = ( %mailing, $mh->_make_general_headers, $mh->list_headers );

            require DADA::Security::Password;
            my $ran_number = DADA::Security::Password::generate_rand_string('1234567890');
            $mailing{'Message-ID'} = '<' . $msg_id . '.' . $ran_number . '.' . $li->{list_owner_email} . '>';
            $message_id = $msg_id;

            $mh->saved_message( $mh->_massaged_for_archive( \%mailing ) );

        }

        if ($message_id) {
            if ( ( $archive_m == 1 ) && ( $process !~ m/test/i ) ) {
                require DADA::MailingList::Archives;
                my $archive = DADA::MailingList::Archives->new( { -list => $list } );
                $archive->set_archive_info( $message_id, $headers{Subject}, undef, undef, $mh->saved_message );

            }
        }
        else {
            $archive_m = 0;
        }

        if ( $args->{-html_output} == 1 ) {
            if ( $process =~ m/test/i ) {
                $self->wait_for_it( $list, $message_id );
                print $q->redirect( -uri => $DADA::Config::S_PROGRAM_URL . '?f='
                      . $flavor
                      . '&test_sent=1&test_recipient='
                      . $og_test_recipient );
            }
            else {

                require DADA::MailingList::MessageDrafts;
                my $d = DADA::MailingList::MessageDrafts->new( { -list => $list } );
                if ( $d->enabled ) {
                    if ( defined($draft_id) ) {
                        $d->remove($draft_id);
                    }
                }
                my $uri = $DADA::Config::S_PROGRAM_URL . '?f=sending_monitor&type=list&id=' . $message_id;
                print $q->redirect( -uri => $uri );
            }
        }

        return;
    }
}

sub send_url_email {

    my $self = shift;
    my ($args) = @_;

    my $q       = $args->{-cgi_obj};
    my $process = xss_filter( strip( $q->param('process') ) );
    my $flavor  = xss_filter( strip( $q->param('flavor') ) );

    my $restore_from_draft = $q->param('restore_from_draft')               || 'true';
    my $test_sent          = xss_filter( strip( $q->param('test_sent') ) ) || 0;
    my $test_recipient     = $q->param('test_recipient');

    my ( $admin_list, $root_login ) = check_list_security(
        -cgi_obj  => $q,
        -Function => 'send_url_email'
    );

    my $list = $admin_list;

    require DADA::MailingList::Settings;

    my $ls = DADA::MailingList::Settings->new( { -list => $list } );
    my $li = $ls->get;

    require DADA::MailingList::Archives;

    my $la = DADA::MailingList::Archives->new( { -list => $list } );
    my $lh = DADA::MailingList::Subscribers->new( { -list => $list } );

    my $can_use_mime_lite_html = 0;
    my $mime_lite_html_error   = undef;
    eval { require DADA::App::MyMIMELiteHTML };
    if ( !$@ ) {
        $can_use_mime_lite_html = 1;
    }
    else {
        $mime_lite_html_error = $@;
    }

    my $can_use_lwp_simple = 0;
    my $lwp_simple_error   = undef;
    eval { require LWP::Simple };
    if ( !$@ ) {
        $can_use_lwp_simple = 1;
    }
    else {
        $lwp_simple_error = $@;

    }

    my $fields = [];

    # Extra, special one...
    push( @$fields, { name => 'subscriber.email' } );
    for my $field ( @{ $lh->subscriber_fields( { -dotted => 1 } ) } ) {
        push( @$fields, { name => $field } );
    }
    my $undotted_fields = [];

    # Extra, special one...
    push( @$undotted_fields, { name => 'email', label => 'Email Address' } );
    require DADA::ProfileFieldsManager;
    my $pfm         = DADA::ProfileFieldsManager->new;
    my $fields_attr = $pfm->get_all_field_attributes;
    for my $undotted_field ( @{ $lh->subscriber_fields( { -dotted => 0 } ) } ) {
        push(
            @$undotted_fields,
            {
                name  => $undotted_field,
                label => $fields_attr->{$undotted_field}->{label}
            }
        );
    }

    if ( !$process ) {

        my ( $num_list_mailouts, $num_total_mailouts, $active_mailouts, $mailout_will_be_queued ) =
          $self->mass_mailout_info($list);

        my $draft_id = undef;

        require DADA::MailingList::MessageDrafts;
        my $d = DADA::MailingList::MessageDrafts->new( { -list => $list } );
        if ( $d->enabled ) {
            if (   $restore_from_draft ne 'true'
                && $d->has_draft( { -screen => 'send_url_email' } ) )
            {
                $draft_id = undef;
            }
            elsif ($restore_from_draft eq 'true'
                && $d->has_draft( { -screen => 'send_url_email' } ) )
            {
                if ( defined( $q->param('draft_id') ) ) {
                    $draft_id = $q->param('draft_id');
                }
                else {
                    $draft_id = $d->latest_draft_id( { -screen => 'send_url_email' } );
                }
            }
        }
        require DADA::Template::Widgets;
        my %wysiwyg_vars = DADA::Template::Widgets::make_wysiwyg_vars($list);

        my $scrn = DADA::Template::Widgets::wrap_screen(
            {
                -screen         => 'send_url_email_screen.tmpl',
                -with           => 'admin',
                -wrapper_params => {
                    -Root_Login => $root_login,
                    -List       => $list,
                },
                -expr => 1,
                -vars => {

                    screen => 'send_url_email',

                    draft_id       => $draft_id,
                    draft_enabled  => $d->enabled,
                    test_sent      => $test_sent,
                    test_recipient => $test_recipient,

                    can_use_mime_lite_html     => $can_use_mime_lite_html,
                    mime_lite_html_error       => $mime_lite_html_error,
                    can_use_lwp_simple         => $can_use_lwp_simple,
                    lwp_simple_error           => $lwp_simple_error,
                    can_display_attachments    => $la->can_display_attachments,
                    fields                     => $fields,
                    undotted_fields            => $undotted_fields,
                    can_have_subscriber_fields => $lh->can_have_subscriber_fields,
                    SERVER_ADMIN               => $ENV{SERVER_ADMIN},
                    priority_popup_menu        => DADA::Template::Widgets::priority_popup_menu($li),

                    global_list_sending_checkbox_widget =>
                      DADA::Template::Widgets::global_list_sending_checkbox_widget($list),

                    MAILOUT_AT_ONCE_LIMIT  => $DADA::Config::MAILOUT_AT_ONCE_LIMIT,
                    mailout_will_be_queued => $mailout_will_be_queued,
                    num_list_mailouts      => $num_list_mailouts,
                    num_total_mailouts     => $num_total_mailouts,
                    active_mailouts        => $active_mailouts,

                    plaintext_message_body_content       => $ls->plaintext_message_body_content,
                    html_message_body_content            => $ls->html_message_body_content,
                    html_message_body_content_js_escaped => js_enc( $ls->html_message_body_content ),
                    %wysiwyg_vars,

                },
                -list_settings_vars       => $ls->params,
                -list_settings_vars_param => { -dot_it => 1, },
            }
        );
        if ( $restore_from_draft eq 'true' ) {
            $scrn = $self->fill_in_draft_msg(
                {
                    -list     => $list,
                    -screen   => 'send_url_email',
                    -str      => $scrn,
                    -draft_id => $draft_id,
                }
            );
        }
        e_print($scrn);

    }
    elsif ( $process eq 'save_as_draft' ) {
        $self->save_as_draft( { -cgi_obj => $q, -list => $list } );
    }
    else {

        if ($can_use_mime_lite_html) {

            my $draft_id = $q->param('draft_id');

            require DADA::App::FormatMessages;

            my $url = strip( $q->param('url') );

            # DEV: Headers.  Ugh, remember this is in, "Send a Webpage" as well.
            my %headers = ();
            for my $h (
                qw(
                Reply-To
                Errors-To
                Return-Path
                X-Priority
                Subject
                )
              )
            {
                if ( defined( $q->param($h) ) ) {
                    $headers{$h} = strip( $q->param($h) );
                }
            }

            #/Headers

            my $url_options       = $q->param('url_options')       || undef;
            my $remove_javascript = $q->param('remove_javascript') || 0;

            my $login_details;
            if (   defined( $q->param('url_username') )
                && defined( $q->param('url_password') ) )
            {
                $login_details = $q->param('url_username') . ':' . $q->param('url_password');
            }

            my $proxy = defined( $q->param('proxy') ) ? $q->param('proxy') : undef;

            my $mailHTML = new DADA::App::MyMIMELiteHTML(
                remove_jscript => $remove_javascript,

                'IncludeType' => $url_options,
                'TextCharset' => $li->{charset_value},
                'HTMLCharset' => $li->{charset_value},

                HTMLEncoding => $li->{html_encoding},
                TextEncoding => $li->{plaintext_encoding},

                ( ($proxy)         ? ( Proxy        => $proxy, )         : () ),
                ( ($login_details) ? ( LoginDetails => $login_details, ) : () ),

                (
                      ( $DADA::Config::CPAN_DEBUG_SETTINGS{MIME_LITE_HTML} == 1 )
                    ? ( Debug => 1, )
                    : ()
                ),
                %headers,
            );

            my $t = $q->param('text_message_body')
              || 'This email message requires that your mail reader support HTML';

            if ( $q->param('auto_create_plaintext') == 1 ) {
                if ( $q->param('content_from') eq 'url' ) {
                    if ( length($url) <= 0 ) {
                        croak "You did not fill in a URL!";
                    }
                    require LWP::Simple;
                    eval { $LWP::Simple::ua->agent( 'Mozilla/5.0 (compatible; ' . $DADA::CONFIG::PROGRAM_NAME . ')' ); };
                    my $good_try = LWP::Simple::get($url);
                    $t = html_to_plaintext(
                        {
                            -str              => $good_try,
                            -formatter_params => {
                                base        => $url,
                                before_link => '<!-- tmpl_var LEFT_BRACKET -->%n<!-- tmpl_var RIGHT_BRACKET -->',
                                footnote    => '<!-- tmpl_var LEFT_BRACKET -->%n<!-- tmpl_var RIGHT_BRACKET --> %l',
                            }
                        }
                    );
                }
                else {
                    $t = html_to_plaintext( { -str => $q->param('html_message_body') } );
                }
            }
            return undef
              if redirect_tag_check( $t, $list, $root_login ) eq undef;

            my $MIMELiteObj;

            if ( $q->param('content_from') eq 'url' ) {

                #/ Redirect tag check
                require LWP::Simple;
                eval { $LWP::Simple::ua->agent( 'Mozilla/5.0 (compatible; ' . $DADA::CONFIG::PROGRAM_NAME . ')' ); };
                my $rtc = LWP::Simple::get($url);
                return undef
                  if redirect_tag_check( $rtc, $list, $root_login ) eq undef;

                # Redirect tag check

                my $errors = undef;
                eval { $MIMELiteObj = $mailHTML->parse( $url, safely_encode($t) ); };

                # DEV: It would be a lot nicer, if this was just printed in our control panel, instead of an error:
                if ($@) {
                    $errors .=
                      "Problems with sending a webpage! Make sure you've correctly entered the URL to your webpage!\n";
                    $errors .= "* Returned Error: $@";
                    eval { $LWP::Simple::ua->agent( 'Mozilla/5.0 (compatible; ' . $DADA::CONFIG::PROGRAM_NAME . ')' ); };
                    my $can_fetch = LWP::Simple::get($url);
                    if ($can_fetch) {
                        $errors .= "* Can successfully fetch, " . $url . "\n";
                    }
                    else {
                        $errors .= "* Cannot fetch, " . $url . " using LWP::Simple::get()\n";
                    }
                    report_mass_mail_errors( $errors, $list, $root_login );
                    return;
                }
            }
            else {
                my $html_message = $q->param('html_message_body');
                my $text_message = undef;
                ( $text_message, $html_message ) =
                  DADA::App::FormatMessages::pre_process_msg_strings( $text_message, $html_message );

                return undef
                  if redirect_tag_check( $html_message, $list, $root_login ) eq undef;
                eval { $MIMELiteObj = $mailHTML->parse( safely_encode($html_message), safely_encode($t) ); };
                if ($@) {
                    my $errors = "Problems sending HTML! \n
* Are you trying to send a webpage via URL instead?
* Have you entered anything in the, HTML Version?
* Returned Error: $@
";
                    report_mass_mail_errors( $errors, $list, $root_login );
                    return;
                }
            }

            my $fm = DADA::App::FormatMessages->new( -List => $list );
            $fm->mass_mailing(1);
            $fm->originating_message_url($url);
            $fm->Subject( $headers{Subject} );

            my $problems         = 0;
            my $eval_error       = '';
            my $rm               = '';
            my @MIME_HTML_errors = ();

            eval { $rm = $MIMELiteObj->as_string; };
            if ($@) {
                warn
                  "$DADA::Config::PROGRAM_NAME $DADA::Config::VER - Send a Webpage isn't functioning correctly? - $@";
                $problems++;
                $eval_error       = $@;
                @MIME_HTML_errors = $mailHTML->errstr;
                for (@MIME_HTML_errors) {
                    $eval_error .= $_;
                }
            }
            else {
                @MIME_HTML_errors = $mailHTML->errstr;
            }

            my $message_id;
            my $mh;

            if ( $q->param('local_archive_options_present') == 1 ) {
                if ( $q->param('archive_message') != 1 ) {
                    $q->param( -name => 'archive_message', -value => 0 );
                }
            }
            my $archive_m = $li->{archive_messages} || 0;
            if (   $q->param('archive_message') == 1
                || $q->param('archive_message') == 0 )
            {
                $archive_m = $q->param('archive_message');
            }

            my $test_recipient = '';

            if ( !$problems ) {
                $rm = safely_decode($rm);

                my ( $header_glob, $template );
                eval {
                    ( $header_glob, $template ) = $fm->format_headers_and_body( -msg => $rm );

                };
                if ($@) {
                    report_mass_mail_errors( $@, $list, $root_login );
                    return;
                }

                require DADA::Mail::Send;

                $mh = DADA::Mail::Send->new(
                    {
                        -list   => $list,
                        -ls_obj => $ls,
                    }
                );

                my %mailing = ( $mh->return_headers($header_glob), Body => $template, );

                my $partial_sending = {};
                for my $field (@$undotted_fields) {
                    if ( $q->param( 'field_comparison_type_' . $field->{name} ) eq 'equal_to' ) {
                        $partial_sending->{ $field->{name} } =
                          { equal_to => $q->param( 'field_value_' . $field->{name} ) };
                    }
                    elsif ( $q->param( 'field_comparison_type_' . $field->{name} ) eq 'like' ) {
                        $partial_sending->{ $field->{name} } = { like => $q->param( 'field_value_' . $field->{name} ) };
                    }
                }
                my $og_test_recipient = '';
                if ( $q->param('archive_no_send') != 1 ) {

                    # Woo Ha! Send away!

                    my @alternative_list = ();
                    @alternative_list = $q->param('alternative_list');

                    $og_test_recipient = $q->param('test_recipient') || '';
                    my $multi_list_send_no_dupes = $q->param('multi_list_send_no_dupes') || 0;

                    $mh->mass_test_recipient($og_test_recipient);
                    $test_recipient = $mh->mass_test_recipient;

                    # send away
                    $message_id = $mh->mass_send(
                        {
                            -msg             => {%mailing},
                            -partial_sending => $partial_sending,
                            -multi_list_send => {
                                -lists    => [@alternative_list],
                                -no_dupes => $multi_list_send_no_dupes,
                            },
                            -also_send_to => [@alternative_list],
                            ( $process =~ m/test/i )
                            ? (
                                -mass_test      => 1,
                                -test_recipient => $og_test_recipient,
                              )
                            : ( -mass_test => 0, )

                        }
                    );

                }
                else {

                    # This is currently similar code as what's in the DADA::Mail::Send::_mail_general_headers method...

                    my $msg_id = DADA::App::Guts::message_id();

                    if ( $q->param('back_date') == 1 ) {
                        $msg_id = $self->backdated_msg_id( { -cgi_obj => $q } );
                    }

                    # time  + random number + sender, woot!
                    require DADA::Security::Password;
                    my $ran_number = DADA::Security::Password::generate_rand_string('1234567890');

                    %mailing = $mh->clean_headers(%mailing);

                    %mailing = ( %mailing, $mh->_make_general_headers, $mh->list_headers );

                    $mailing{'Message-ID'} = '<' . $msg_id . '.' . $ran_number . '.' . $li->{list_owner_email} . '>';

                    $message_id = $msg_id;

                    $mh->saved_message( $mh->_massaged_for_archive( \%mailing ) );

                }

                if ( $archive_m == 1 && ( $q->param('process') !~ m/test/i ) ) {

                    require DADA::MailingList::Archives;

                    my $archive = DADA::MailingList::Archives->new( { -list => $list } );
                    $archive->set_archive_info( $message_id, $q->param('Subject'), undef, undef, $mh->saved_message );

                }

                if ( $process =~ m/test/i ) {
                    $self->wait_for_it( $list, $message_id );
                    print $q->redirect( -uri => $DADA::Config::S_PROGRAM_URL . '?f='
                          . $flavor
                          . '&test_sent=1&test_recipient='
                          . $og_test_recipient );
                }
                else {
                    require DADA::MailingList::MessageDrafts;
                    my $d = DADA::MailingList::MessageDrafts->new( { -list => $list } );
                    if ( $d->enabled ) {
                        $d->remove($draft_id);
                    }
                    my $uri = $DADA::Config::S_PROGRAM_URL . '?f=sending_monitor&type=list&id=' . $message_id;
                    print $q->redirect( -uri => $uri );
                }
            }
            else {
                # DEV: This should probably be fleshed out to be a bit more verbose...
                report_mass_mail_errors( $eval_error, $list, $root_login );
                return;
            }

        }
        else {
            die "$DADA::Config::PROGRAM_NAME $DADA::Config::VER Error: $!\n";
        }
    }
}

sub wait_for_it {
    my $self       = shift;
    my $list       = shift;
    my $message_id = shift;

    my $still_working = 1;
    my $tries         = 0;
    require DADA::Mail::MailOut;
  SENDING_CHECK: while ($still_working) {
        $tries++;
        if ( DADA::Mail::MailOut::mailout_exists( $list, $message_id, 'list' ) == 1 ) {
            sleep(3);
        }
        else {
            $still_working = 0;
            last SENDING_CHECK;
        }
        if ( $tries > 5 ) {
            last SENDING_CHECK;
        }
    }
    return 1;
}

sub save_as_draft {

    my $self = shift;
    my ($args) = @_;

    my $q = $args->{-cgi_obj};
    my $list;

    if ( !exists( $args->{-list} ) ) {
        croak "You must pass the -list parameter!";
    }
    else {
        $list = $args->{-list};
    }

    require DADA::MailingList::MessageDrafts;
    my $d = DADA::MailingList::MessageDrafts->new( { -list => $list } );

    return unless $d->enabled;

    my $draft_id = $q->param('draft_id') || undef;

    # warn '$draft_id:' . $draft_id;
    my $saved_draft_id = $d->save(
        {
            -cgi_obj => $q,
            -id      => $draft_id,
            -screen  => $q->param('f'),
        }
    );

    # warn '$saved_draft_id:' . $saved_draft_id;

    require JSON::PP;
    my $json = JSON::PP->new->allow_nonref;
    my $return = { id => $saved_draft_id };
    print $q->header(
        '-Cache-Control' => 'no-cache, must-revalidate',
        -expires         => 'Mon, 26 Jul 1997 05:00:00 GMT',
        -type            => 'application/json',
    );
    print $json->pretty->encode($return);
}

sub list_invite {

    my $self   = shift;
    my ($args) = @_;
    my $q      = $args->{-cgi_obj};

    my $process = xss_filter( strip( $q->param('process') ) );
    warn '$process ' . $process;
    my $flavor = xss_filter( strip( $q->param('flavor') ) );

    my ( $admin_list, $root_login ) = check_list_security(
        -cgi_obj  => $q,
        -Function => 'list_invite'
    );
    my $list = $admin_list;

    require DADA::MailingList::Settings;
    my $ls = DADA::MailingList::Settings->new( { -list => $list } );
    my $li = $ls->get;

    my $lh = DADA::MailingList::Subscribers->new( { -list => $list } );

    if ( $process =~ m/send invitation\.\.\./i )
    {    # $process is dependent on the label of the button - which is not a good idea

        my ( $num_list_mailouts, $num_total_mailouts, $active_mailouts, $mailout_will_be_queued ) =
          $self->mass_mailout_info($list);

        my $field_names       = [];
        my $subscriber_fields = $lh->subscriber_fields;
        for (@$subscriber_fields) {
            push( @$field_names, { name => $_ } );
        }

        my @addresses = $q->param('address');

        my $verified_addresses        = [];
        my $invited_already_addresses = [];

        # Addresses hold CSV info - each item in the array is one line of CSV...

        for my $a (@addresses) {
            my $pre_info = $lh->csv_to_cds($a);
            my $info     = {};

            # DEV: Here I got again:
            $info->{email} = $pre_info->{email};

            my $new_fields = [];
            my $i          = 0;
            for (@$subscriber_fields) {
                push( @$new_fields, { name => $_, value => $pre_info->{fields}->{$_} } );
                $i++;    # and then, $i is never used, again?
            }

            $info->{fields} = $new_fields;

            #And... Then this!
            $info->{csv_info} = $a;
            $info->{'list_settings.invites_prohibit_reinvites'} = $ls->param('invites_prohibit_reinvites');
            if ( $ls->param('invites_check_for_already_invited') == 1 ) {

                # invited, already?
                if (
                    $lh->check_for_double_email(
                        -Email => $info->{email},
                        -Type  => 'invited_list'
                    ) == 1
                  )
                {
                    push( @$invited_already_addresses, $info );
                }
                else {
                    push( @$verified_addresses, $info );
                }
            }
            else {
                push( @$verified_addresses, $info );
            }
        }

        require DADA::Template::Widgets;
        my $scrn = DADA::Template::Widgets::wrap_screen(
            {
                -screen         => 'list_invite_screen.tmpl',
                -with           => 'admin',
                -wrapper_params => {
                    -Root_Login => $root_login,
                    -List       => $list,
                },
                -expr => 1,
                -vars => {
                    using_no_wysiwyg_editor => 1,

                    screen => 'add',
                    list_type_isa_list =>
                      1,    # I think this only works with Subscribers at the moment, so no need to do a harder check...
                            # This is sort of weird, as it default to the "Send a Message" Subject
                    mass_mailing_type => 'invite',
                    Subject           => $ls->param('invite_message_subject'),
                    field_names       => $field_names,

                    verified_addresses        => $verified_addresses,
                    invited_already_addresses => $invited_already_addresses,

                    html_message_body_content            => $li->{invite_message_html},
                    html_message_body_content_js_escaped => js_enc( $li->{invite_message_html} ),
                    MAILOUT_AT_ONCE_LIMIT                => $DADA::Config::MAILOUT_AT_ONCE_LIMIT,
                    mailout_will_be_queued               => $mailout_will_be_queued,
                    num_list_mailouts                    => $num_list_mailouts,
                    num_total_mailouts                   => $num_total_mailouts,
                    active_mailouts                      => $active_mailouts,

                    using_no_wysiwyg_editor => 1,
                },
                -list_settings_vars       => $li,
                -list_settings_vars_param => { -dot_it => 1, },
            }
        );
        e_print($scrn);

    }
    elsif ( $process =~ m/send test invitation|send a test invitation|send invitations/i )
    {    # $process is dependent on the label of the button - which is not a good idea

        my @address                 = $q->param('address');
        my @already_invited_address = $q->param('already_invited_address');

        # This is a little safety - there shouldn't be anything in
        # @already_invited_address anyways.
        if ( $ls->param('invites_prohibit_reinvites') != 1 ) {
            @address = ( @address, @already_invited_address );
        }

        for my $a (@address) {
            my $info = $lh->csv_to_cds($a);
            $lh->add_subscriber(
                {
                    -email  => $info->{email},
                    -fields => $info->{fields},
                    -type   => 'invitelist',
                }
            );
            $lh->add_subscriber(
                {
                    -email      => $info->{email},
                    -fields     => $info->{fields},
                    -type       => 'sub_confirm_list',
                    -dupe_check => {
                        -enable  => 1,
                        -on_dupe => 'ignore_add',
                    },
                }
            );

            # Should this happen for TESTS as well?!
            $lh->add_subscriber(
                {
                    -email      => $info->{email},
                    -fields     => $info->{fields},
                    -type       => 'invited_list',
                    -dupe_check => {
                        -enable  => 1,
                        -on_dupe => 'ignore_add',
                    },
                }
            );

        }

        # DEV: Headers.  Ugh, remember this is in, "Send a Webpage" as well.
        my %headers = ();
        for my $h (
            qw(
            Reply-To
            Errors-To
            Return-Path
            X-Priority
            Subject
            )
          )
        {
            if ( defined( $q->param($h) ) ) {
                $headers{$h} = strip( $q->param($h) );
            }
        }

        #/Headers

        require DADA::App::FormatMessages;

        my $text_message_body = $q->param('text_message_body') || undef;
        if ( $q->param('use_text_message') != 1 ) {
            $text_message_body = undef;
        }
        my $html_message_body = $q->param('html_message_body') || undef;
        if ( $q->param('use_html_message') != 1 ) {
            $html_message_body = undef;
        }

        if ( $text_message_body eq undef && $html_message_body eq undef ) {
            report_mass_mail_errors( "Message will be sent blank! Stopping!", $list, $root_login );
            return;
        }

        ( $text_message_body, $html_message_body ) =
          DADA::App::FormatMessages::pre_process_msg_strings( $text_message_body, $html_message_body );

        require MIME::Lite;
        $MIME::Lite::PARANOID = $DADA::Config::MIME_PARANOID;
        my $msg;

        if ( $text_message_body and $html_message_body ) {

            $text_message_body = safely_encode($text_message_body);
            $html_message_body = safely_encode($html_message_body);

            return undef
              if redirect_tag_check( $text_message_body, $list, $root_login ) eq undef;
            return undef
              if redirect_tag_check( $html_message_body, $list, $root_login ) eq undef;

            $msg = MIME::Lite->new(
                Type      => 'multipart/alternative',
                Datestamp => 0,
                %headers,
            );
            $msg->attr( 'content-type.charset' => $li->{charset_value} );

            my $pt_part = MIME::Lite->new(
                Type     => 'TEXT',
                Data     => $text_message_body,
                Encoding => $li->{plaintext_encoding},
            );
            $pt_part->attr( 'content-type.charset' => $li->{charset_value} );
            $msg->attach($pt_part);

            my $html_part = MIME::Lite->new(
                Type     => 'text/html',
                Data     => $html_message_body,
                Encoding => $li->{html_encoding},
            );
            $html_part->attr( 'content-type.charset' => $li->{charset_value} );
            $msg->attach($html_part);

        }
        elsif ($html_message_body) {

            $html_message_body = safely_encode($html_message_body);

            return undef
              if redirect_tag_check( $html_message_body, $list, $root_login ) eq undef;

            $msg = MIME::Lite->new(
                Type      => 'text/html',
                Data      => $html_message_body,
                Encoding  => $li->{html_encoding},
                Datestamp => 0,
                %headers,
            );
            $msg->attr( 'content-type.charset' => $li->{charset_value} );

        }
        elsif ($text_message_body) {
            $text_message_body = safely_encode($text_message_body);

            return undef
              if redirect_tag_check( $text_message_body, $list, $root_login ) eq undef;
            $msg = MIME::Lite->new(
                Type      => 'text/plain',
                Data      => $text_message_body,
                Datestamp => 0,
                Encoding  => $li->{plaintext_encoding},
                %headers,
            );
            $msg->attr( 'content-type.charset' => $li->{charset_value} );
        }
        else {

            warn
"$DADA::Config::PROGRAM_NAME $DADA::Config::VER warning: both text and html versions of invitation message blank?!";

            return undef
              if redirect_tag_check( $ls->param('invite_message_text'), $list, $root_login ) eq undef;
            $msg = MIME::Lite->new(
                Type      => 'TEXT',
                Data      => safely_encode( $ls->param('invite_message_text') ),
                Datestamp => 0,
                Encoding  => $li->{plaintext_encoding},
                %headers,
            );
            $msg->attr( 'content-type.charset' => $li->{charset_value} );

        }

        $msg->replace( 'X-Mailer' => "" );

        my $msg_as_string = ( defined($msg) ) ? $msg->as_string : undef;
        $msg_as_string = safely_encode($msg_as_string);

        require DADA::App::FormatMessages;
        my $fm = DADA::App::FormatMessages->new( -List => $list );
        $fm->Subject( $headers{Subject} );
        $fm->mass_mailing(1);
        $fm->use_email_templates(0);
        $fm->list_type('invitelist');
        my ( $header_glob, $message_string );
        eval { ( $header_glob, $message_string ) = $fm->format_headers_and_body( -msg => $msg_as_string ); };

        if ($@) {
            report_mass_mail_errors( $@, $list, $root_login );
            return;
        }

        require DADA::Mail::Send;

        my $mh = DADA::Mail::Send->new(
            {
                -list   => $list,
                -ls_obj => $ls,
            }
        );

        # translate the glob into a hash

        $mh->list_type('invitelist');

        $mh->mass_test(1)
          if ( $process =~ m/test/i );

        my $test_recipient = '';
        if ( $process =~ m/test/i ) {
            $mh->mass_test_recipient( strip( $q->param('test_recipient') ) );
            $test_recipient = $mh->mass_test_recipient;
        }

        my $message_id = $mh->mass_send( $mh->return_headers($header_glob), Body => $message_string, );

        my $uri = $DADA::Config::S_PROGRAM_URL . '?f=sending_monitor&type=invitelist&id=' . $message_id;
        print $q->redirect( -uri => $uri );

    }
    else {
        die "unknown process type? Whazah?!";
    }
}

sub fill_in_draft_msg {
    my $self = shift;
    my ($args) = @_;

    for ( '-list', '-screen', '-str', '-draft_id' ) {
        if ( !exists( $args->{$_} ) ) {
            croak "You MUST pass the, '$_' parameter!";
        }
    }
    my $str;

    require DADA::MailingList::MessageDrafts;
    my $d = DADA::MailingList::MessageDrafts->new( { -list => $args->{-list} } );
    return $args->{-str}
      unless ( $d->enabled );
    if ( $d->has_draft( { -screen => $args->{-screen} } ) ) {
        my $q_draft = $d->fetch( { -id => $args->{-draft_id}, -screen => $args->{-screen} } );
        require HTML::FillInForm::Lite;
        my $h       = HTML::FillInForm::Lite->new();
        my $tmp_str = $args->{-str};
        $str = $h->fill( \$tmp_str, $q_draft, fill_password => 1 );
        return $str;
    }
    else {
        $args->{-str};
    }
}

sub has_attachments {

    my $self = shift;

    my ($args) = @_;
    my $q = $args->{-cgi_obj};

    my @ive_got = ();

    my $num = 5;

    for ( 1 .. $num ) {
        my $filename = $q->param( 'attachment' . $_ );
        warn '$filename:' . $filename
          if $t;
        if ( defined($filename) && length($filename) > 1 ) {
            if ( $filename ne 'Select A File...' && length($filename) > 0 ) {
                warn 'I\'ve got, ' . 'attachment' . $_
                  if $t;
                if ( !-e $DADA::Config::FILE_BROWSER_OPTIONS->{kcfinder}->{upload_dir} . '/' . $filename ) {
                    my $new_filename = uriunescape($filename);
                    if ( !-e $DADA::Config::FILE_BROWSER_OPTIONS->{kcfinder}->{upload_dir} . '/' . $new_filename ) {
                        carp
"I can't find attachment file: $DADA::Config::FILE_BROWSER_OPTIONS->{kcfinder}->{upload_dir} . '/' . $filename";
                    }
                    else {
                        push( @ive_got, $new_filename );
                    }
                }
                else {
                    push( @ive_got, $filename );
                }
            }
        }
    }
    return @ive_got;
}

sub make_attachment {

    my $self   = shift;
    my ($args) = @_;
    my $name   = $args->{-name};

    require MIME::Lite;

    if ( !$name ) {
        warn '!$name';
        return undef;
    }

    warn '$name:: ' . $name
      if $t;

    my $filename = $name;
    $filename =~ s/(.*?)\///;

    warn '$filename: ' . $filename
      if $t;

    my $a_type = $self->find_attachment_type($filename);

    warn '$a_type: ' . $a_type
      if $t;

    $filename =~ s!^.*(\\|\/)!!;
    $filename =~ s/\s/%20/g;

    my %mime_args = (
        Type        => $a_type,
        Disposition => $self->make_a_disposition($a_type),
        Datestamp   => 0,
        Id          => $filename,
        Filename    => $filename,
        Path        => $DADA::Config::FILE_BROWSER_OPTIONS->{kcfinder}->{upload_dir} . '/' . $name,
    );

    if ($t) {
        require Data::Dumper;
        warn '%mime_args' . Data::Dumper::Dumper( {%mime_args} );
    }

    my $msg_att = MIME::Lite->new(%mime_args);
    $msg_att->attr( 'Content-Location' => $filename );

    return $msg_att;

}

sub make_a_disposition {

    my $self        = shift;
    my $n           = shift;
    my $disposition = 'inline';

    if ( $n !~ m/image/ ) {

        #if($n !~ /text/){ # if they're inline, they get parsed as if
        # they were a part of Dada Mail... hmm...
        $disposition = 'attachment';

        #}
    }

    return $disposition;

}

sub find_attachment_type {

    my $self = shift;

    my $filename = shift;
    my $a_type;

    my $attach_name = $filename;
    $attach_name =~ s!^.*(\\|\/)!!;
    $attach_name =~ s/\s/%20/g;

    my $file_ending = $attach_name;
    $file_ending =~ s/.*\.//;

    require MIME::Types;
    require MIME::Type;

    if ( ( $MIME::Types::VERSION >= 1.005 ) && ( $MIME::Type::VERSION >= 1.005 ) ) {
        my ( $mimetype, $encoding ) = MIME::Types::by_suffix($filename);
        $a_type = $mimetype
          if ( $mimetype && $mimetype =~ /^\S+\/\S+$/ );    ### sanity check
    }
    else {
        if ( exists( $DADA::Config::MIME_TYPES{ '.' . lc($file_ending) } ) ) {
            $a_type = $DADA::Config::MIME_TYPES{ '.' . lc($file_ending) };
        }
        else {
            $a_type = $DADA::Config::DEFAULT_MIME_TYPE;
        }
    }
    if ( !$a_type ) {
        warn "attachment MIME Type never figured out, letting MIME::Lite handle this...";
        $a_type = 'AUTO';
    }

    return $a_type;
}

sub backdated_msg_id {

    my $self          = shift;
    my ($args)        = @_;
    my $q             = $args->{-cgi_obj};
    my $backdate_hour = $q->param('backdate_hour');
    $backdate_hour = int($backdate_hour) + 12
      if $q->param('backdate_hour_label') =~ /p/;    # as in, p.m.

    my $message_id = sprintf(
        "%02d%02d%02d%02d%02d%02d",
        $q->param('backdate_year'), $q->param('backdate_month'),  $q->param('backdate_day'),
        $backdate_hour,             $q->param('backdate_minute'), $q->param('backdate_second')
    );
    return $message_id;

}

sub mass_mailout_info {

    my $self                   = shift;
    my $list                   = shift;
    my $num_list_mailouts      = undef;
    my $num_total_mailouts     = undef;
    my $mailout_will_be_queued = undef;

    my (
        $monitor_mailout_report, $total_mailouts,  $active_mailouts,
        $paused_mailouts,        $queued_mailouts, $inactive_mailouts
    );

    eval {
        require DADA::Mail::MailOut;

        my @mailouts = DADA::Mail::MailOut::current_mailouts( { -list => $list } );
        $num_list_mailouts = $#mailouts + 1;

        (
            $monitor_mailout_report, $total_mailouts,  $active_mailouts,
            $paused_mailouts,        $queued_mailouts, $inactive_mailouts
          )
          = DADA::Mail::MailOut::monitor_mailout(
            {
                -verbose => 0,
                -list    => $list,
                -action  => 0,
            }
          );
        $num_total_mailouts = $total_mailouts;
    };
    if ($@) {
        warn
"Problems filling out the 'Sending Monitor' admin menu item with interesting bits of information about the mailouts: $@";
    }
    else {

        if ( $DADA::Config::MAILOUT_AT_ONCE_LIMIT ne undef ) {

            # DEV: 2203220  	 3.0.0 - Stale Mailout can still clog up mail queue
            # https://sourceforge.net/tracker2/?func=detail&aid=2203220&group_id=13002&atid=113002
            # We've got to look at *active* mailouts, first
            # We don't care about paused or inactive mailouts - any of that,
            if ( $active_mailouts >= $DADA::Config::MAILOUT_AT_ONCE_LIMIT ) {
                $mailout_will_be_queued = 1;
            }
        }
    }
    return ( $num_list_mailouts, $num_total_mailouts, $active_mailouts, $mailout_will_be_queued );

}

sub redirect_tag_check {

    my ( $str, $list, $root_login ) = @_;
    require DADA::MailingList::Settings;
    my $ls = DADA::MailingList::Settings->new( { -list => $list } );
    require DADA::Logging::Clickthrough;
    my $ct = DADA::Logging::Clickthrough->new(
        {
            -list => $list,
            -ls   => $ls,
        }
    );
    if ( !$ct->enabled ) {
        return 1;

        #			report_mass_mail_errors('Clickthrough is not enabled for this backend.', $list, $root_login);
        #			return undef;
    }
    eval { $ct->check_redirect_urls( { -str => $str, -raise_error => 1, } ); };
    if ($@) {
        report_mass_mail_errors( $@, $list, $root_login );
        return undef;
    }
    else {
        return 1;
    }

}

sub report_mass_mail_errors {
    my $errors     = shift;
    my $list       = shift;
    my $root_login = shift;

    my $tmpl = q{ 

};

    require DADA::Template::Widgets;
    my $scrn = DADA::Template::Widgets::wrap_screen(
        {
            -with           => 'admin',
            -wrapper_params => {
                -Root_Login => $root_login,
                -List       => $list,
            },
            -screen => 'report_mass_mailing_errors_screen.tmpl',
            -vars   => { errors => $errors }
        }
    );
    print $scrn;
}

sub just_subscribed_mass_mailing {

    my ($args) = @_;
    if ( !exists( $args->{-list} ) ) {
        croak "You MUST pass a list in the, '-list' parameter!";
    }
    if ( !$args->{-addresses}->[0] ) {
        return;
    }

    # Subscribe 'em
    require DADA::MailingList::Subscribers;
    my $lh = DADA::MailingList::Subscribers->new( { -list => $args->{-list} } );

    my $type = '_tmp-just_subscribed-' . time;

    for my $a ( @{ $args->{-addresses} } ) {
        my $info = $lh->csv_to_cds($a);
        my $dmls = $lh->add_subscriber(
            {
                -email      => $info->{email},
                -type       => $type,
                -dupe_check => {
                    -enable  => 1,
                    -on_dupe => 'ignore_add',
                },
            }
        );
    }

    require DADA::App::FormatMessages;
    my $fm = DADA::App::FormatMessages->new( -List => $args->{-list} );
    $fm->mass_mailing(1);
    $fm->list_type('just_subscribed');
    $fm->use_email_templates(0);

    require DADA::MailingList::Settings;
    my $ls = DADA::MailingList::Settings->new( { -list => $args->{-list} } );
    my ( $header_glob, $message_string ) = $fm->format_headers_and_body(
        -msg => $fm->string_from_dada_style_args(
            {
                -fields => {
                    Subject => $ls->param('subscribed_by_list_owner_message_subject'),
                    Body    => $ls->param('subscribed_by_list_owner_message'),
                },
            }
        )
    );

    require DADA::Mail::Send;
    my $mh = DADA::Mail::Send->new( { -list => $args->{-list} } );
    $mh->list_type($type);
    my $message_id = $mh->mass_send( { -msg => { $mh->return_headers($header_glob), Body => $message_string, }, } );
    return 1;

}

sub just_unsubscribed_mass_mailing {

    my ($args) = @_;
    if ( !exists( $args->{-list} ) ) {
        croak "You MUST pass a list in the, '-list' parameter!";
    }

    my $type = '_tmp-just_unsubscribed-' . time;
    require DADA::MailingList::Subscribers;
    my $lh = DADA::MailingList::Subscribers->new( { -list => $args->{-list} } );

    if ( !$args->{-addresses}->[0] ) {
        if ( exists( $args->{-send_to_everybody} ) ) {
            $lh->clone(
                {
                    -from => 'list',
                    -to   => $type,
                }
            );
        }
        else {
            return;
        }
    }
    else {
        for my $a ( @{ $args->{-addresses} } ) {
            my $dmls = $lh->add_subscriber(
                {
                    -email      => $a,
                    -type       => $type,
                    -dupe_check => {
                        -enable  => 1,
                        -on_dupe => 'ignore_add',
                    },
                }
            );
        }
    }

    require DADA::App::FormatMessages;
    my $fm = DADA::App::FormatMessages->new( -List => $args->{-list} );
    $fm->use_email_templates(0);
    $fm->mass_mailing(1);
    $fm->list_type('just_unsubscribed');

    require DADA::MailingList::Settings;
    my $ls = DADA::MailingList::Settings->new( { -list => $args->{-list} } );
    my ( $header_glob, $message_string ) = $fm->format_headers_and_body(
        -msg => $fm->string_from_dada_style_args(
            {
                -fields => {
                    Subject => $ls->param('unsubscribed_by_list_owner_message_subject'),
                    Body    => $ls->param('unsubscribed_by_list_owner_message'),
                },
            }
        )
    );

    require DADA::Mail::Send;
    my $mh = DADA::Mail::Send->new( { -list => $args->{-list} } );
    $mh->list_type($type);
    my $message_id = $mh->mass_send( { -msg => { $mh->return_headers($header_glob), Body => $message_string, }, } );
    return 1;
}

sub send_last_archived_msg_mass_mailing {

    my ($args) = @_;
    if ( !exists( $args->{-list} ) ) {
        croak "You MUST pass a list in the, '-list' parameter!";
    }
    if ( !$args->{-addresses}->[0] ) {
        return;
    }

    require DADA::MailingList::Archives;
    my $la = DADA::MailingList::Archives->new( { -list => $args->{-list} } );
    my $entries = $la->get_archive_entries();
    if ( scalar(@$entries) <= 0 ) {
        return;
    }

    # Subscribe 'em
    require DADA::MailingList::Subscribers;
    my $lh = DADA::MailingList::Subscribers->new( { -list => $args->{-list} } );

    my $type = '_tmp-just_subed_archive-' . time;

    for my $a ( @{ $args->{-addresses} } ) {
        my $info = $lh->csv_to_cds($a);
        my $dmls = $lh->add_subscriber(
            {
                -email      => $info->{email},
                -type       => $type,
                -dupe_check => {
                    -enable  => 1,
                    -on_dupe => 'ignore_add',
                },
            }
        );
    }

    my $newest_entry = $la->newest_entry;

    my ( $head, $body ) = $la->massage_msg_for_resending(
        -key     => $newest_entry,
        '-split' => 1,
    );

    require DADA::Mail::Send;
    my $mh = DADA::Mail::Send->new( { -list => $args->{-list} } );
    $mh->list_type($type);
    my $message_id = $mh->mass_send( { -msg => { $mh->return_headers($head), Body => $body, }, } );
    return 1;
}

sub DESTROY {

    my $self = shift;

}

1;

