<?php
/**
 * Post-install phpBB setup: Grok user, private board, forums, table BBCodes.
 */
define('IN_PHPBB', true);
define('IN_CRON', true);

$phpbb_root_path = '/var/www/phpbb/';
$phpEx = 'php';

require $phpbb_root_path . 'common.' . $phpEx;
require $phpbb_root_path . 'includes/functions_user.' . $phpEx;
require $phpbb_root_path . 'includes/functions_admin.' . $phpEx;

$user->session_begin();
$auth->acl($user->data);
$user->setup();

function grokboard_env($name, $default)
{
	$v = getenv($name);
	return ($v !== false && $v !== '') ? $v : $default;
}

function grokboard_config_set($name, $value)
{
	global $config;
	$config->set($name, $value);
}

$board_name = grokboard_env('BOARD_NAME', 'Grok Board');
$board_desc = grokboard_env('BOARD_DESC', 'Just you and Grok. Real phpBB. Actual threads.');
$admin_email = grokboard_env('ADMIN_EMAIL', 'admin@localhost');
$board_email = grokboard_env('BOARD_EMAIL', $admin_email);
$board_contact = grokboard_env('BOARD_CONTACT', $board_email);
$grok_bot_email = grokboard_env('GROK_BOT_EMAIL', 'grok@localhost');
$tz = grokboard_env('TZ', 'UTC');

grokboard_config_set('sitename', $board_name);
grokboard_config_set('site_desc', $board_desc);
grokboard_config_set('require_activation', 3); // disable registration
grokboard_config_set('board_contact', $board_contact);
grokboard_config_set('board_email', $board_email);
grokboard_config_set('email_enable', 0);
grokboard_config_set('coppa_enable', 0);
grokboard_config_set('allow_quick_reply', 1);
grokboard_config_set('posts_per_page', 15);
grokboard_config_set('topics_per_page', 25);
grokboard_config_set('load_db_track', 1);
grokboard_config_set('allow_bbcode', 1);
grokboard_config_set('allow_smilies', 1);
grokboard_config_set('allow_post_links', 1);
grokboard_config_set('auth_bbcode_pm', 1);
grokboard_config_set('grok_model', 'grok-build');
grokboard_config_set('grok_enabled', 1);

// Rename default forums
$sql = 'UPDATE ' . FORUMS_TABLE . " SET forum_name = '" . $db->sql_escape($board_name) . "', forum_desc = 'You and Grok.' WHERE forum_id = 1";
$db->sql_query($sql);
$sql = 'UPDATE ' . FORUMS_TABLE . " SET forum_name = 'Lounge', forum_desc = 'Primary chat. New topic = new conversation. Grok replies in the thread.' WHERE forum_id = 2";
$db->sql_query($sql);

$sql = 'SELECT * FROM ' . FORUMS_TABLE . ' WHERE forum_id = 2';
$result = $db->sql_query($sql);
$template_forum = $db->sql_fetchrow($result);
$db->sql_freeresult($result);

function grokboard_ensure_forum($name, $desc, $template_forum)
{
	global $db;
	$sql = 'SELECT forum_id FROM ' . FORUMS_TABLE . ' WHERE forum_name = \'' . $db->sql_escape($name) . '\'';
	$result = $db->sql_query($sql);
	$row = $db->sql_fetchrow($result);
	$db->sql_freeresult($result);
	if ($row)
	{
		return (int) $row['forum_id'];
	}
	$copy = $template_forum;
	unset($copy['forum_id']);
	$copy['forum_name'] = $name;
	$copy['forum_desc'] = $desc;
	$copy['forum_parents'] = '';
	$sql = 'INSERT INTO ' . FORUMS_TABLE . ' ' . $db->sql_build_array('INSERT', $copy);
	$db->sql_query($sql);
	return (int) $db->sql_nextid();
}

if ($template_forum)
{
	grokboard_ensure_forum('Workshop', 'Code, configs, diffs. Use [code]. Grok answers in-thread.', $template_forum);
	grokboard_ensure_forum('Random', 'Off-topic. Same rules: one thread per tangent.', $template_forum);
}

// Grok bot user
$sql = 'SELECT user_id FROM ' . USERS_TABLE . " WHERE username_clean = 'grok'";
$result = $db->sql_query($sql);
$row = $db->sql_fetchrow($result);
$db->sql_freeresult($result);

if ($row)
{
	$grok_id = (int) $row['user_id'];
}
else
{
	$pass = bin2hex(random_bytes(16));
	$user_row = [
		'username'				=> 'Grok',
		'user_password'			=> phpbb_hash($pass),
		'user_email'			=> $grok_bot_email,
		'group_id'				=> 2,
		'user_type'				=> USER_NORMAL,
		'user_ip'				=> '127.0.0.1',
		'user_regdate'			=> time(),
		'user_inactive_reason'	=> 0,
		'user_inactive_time'	=> 0,
		'user_lastmark'			=> time(),
		'user_lastvisit'		=> 0,
		'user_lang'				=> 'en',
		'user_timezone'			=> $tz,
		'user_dateformat'		=> 'D M d, Y g:i a',
		'user_style'			=> (int) $config['default_style'],
		'user_rank'				=> 0,
		'user_colour'			=> '105289',
		'user_allow_viewemail'	=> 0,
		'user_allow_massemail'	=> 0,
		'user_notify'			=> 0,
		'user_notify_pm'		=> 0,
		'user_sig'				=> 'Grok · xAI · posting live',
	];
	$grok_id = user_add($user_row);
}

if ($grok_id)
{
	grokboard_config_set('grok_user_id', $grok_id);
	$sql = 'UPDATE ' . USERS_TABLE . " SET user_colour = '105289', username = 'Grok' WHERE user_id = " . (int) $grok_id;
	$db->sql_query($sql);
}

// Guests: cannot read forums (private board)
$sql = 'SELECT auth_option_id FROM ' . ACL_OPTIONS_TABLE . " WHERE auth_option = 'f_read'";
$result = $db->sql_query($sql);
$read_id = (int) $db->sql_fetchfield('auth_option_id');
$db->sql_freeresult($result);
if ($read_id)
{
	$sql = 'DELETE FROM ' . ACL_GROUPS_TABLE . ' WHERE group_id = 1 AND auth_option_id = ' . $read_id;
	$db->sql_query($sql);
	$sql = 'DELETE FROM ' . ACL_GROUPS_TABLE . ' WHERE group_id = 1 AND forum_id > 0 AND auth_role_id IN (
		SELECT role_id FROM ' . ACL_ROLES_TABLE . " WHERE role_type = 'f_' AND role_name IN ('ROLE_FORUM_READONLY', 'ROLE_FORUM_LIMITED', 'ROLE_FORUM_STANDARD', 'ROLE_FORUM_FULL', 'ROLE_FORUM_NEW_MEMBER')
	)";
	// subquery may fail on some mysql modes; fall back to zeroing guest forum roles
}

$sql = 'UPDATE ' . ACL_GROUPS_TABLE . ' SET auth_setting = 0 WHERE group_id = 1 AND forum_id > 0';
$db->sql_query($sql);

// Table BBCodes if missing
function grokboard_add_bbcode($tag, $match, $tpl, $helpline)
{
	global $db;
	$sql = 'SELECT bbcode_id FROM ' . BBCODES_TABLE . ' WHERE bbcode_tag = \'' . $db->sql_escape($tag) . '\'';
	$result = $db->sql_query($sql);
	$exists = $db->sql_fetchrow($result);
	$db->sql_freeresult($result);
	if ($exists)
	{
		return;
	}
	$sql = 'SELECT MAX(bbcode_id) AS id FROM ' . BBCODES_TABLE;
	$result = $db->sql_query($sql);
	$next = (int) $db->sql_fetchfield('id');
	$db->sql_freeresult($result);
	$next = max(13, $next + 1);
	if ($next > 151)
	{
		return;
	}
	$sql_ary = [
		'bbcode_id'				=> $next,
		'bbcode_tag'			=> $tag,
		'bbcode_helpline'		=> $helpline,
		'display_on_posting'	=> 1,
		'bbcode_match'			=> $match,
		'bbcode_tpl'			=> $tpl,
		'first_pass_match'		=> '!\\[' . $tag . '\\](.*?)\\[/' . $tag . '\\]!is',
		'first_pass_replace'	=> '[' . $tag . ':$uid]$1[/' . $tag . ':$uid]',
		'second_pass_match'		=> '!\\[' . $tag . ':$uid\\](.*?)\\[/' . $tag . ':$uid\\]!s',
		'second_pass_replace'	=> str_replace('{TEXT}', '$1', $tpl),
	];
	$db->sql_query('INSERT INTO ' . BBCODES_TABLE . ' ' . $db->sql_build_array('INSERT', $sql_ary));
}

grokboard_add_bbcode('table', '[table]{TEXT}[/table]', '<table class="bbcode-table">{TEXT}</table>', 'Table: [table][tr][td]cell[/td][/tr][/table]');
grokboard_add_bbcode('tr', '[tr]{TEXT}[/tr]', '<tr>{TEXT}</tr>', 'Table row');
grokboard_add_bbcode('td', '[td]{TEXT}[/td]', '<td>{TEXT}</td>', 'Table cell');

echo "setup ok grok_user_id=" . (int) $config['grok_user_id'] . PHP_EOL;
