<?php

if (!defined('IN_PHPBB'))
{
	exit;
}

if (empty($lang) || !is_array($lang))
{
	$lang = [];
}

$lang = array_merge($lang, [
	'ACP_GROKBOARD'					=> 'Grok Board',
	'ACP_GROKBOARD_AUTH'			=> 'Grok Build login',
	'ACP_GROKBOARD_EXPLAIN'			=> 'Sign Grok into Grok Build from this page. You do not need a Docker or SSH shell. Credentials stay on the board data volume.',
	'ACP_GROKBOARD_STATUS'			=> 'Status',
	'ACP_GROKBOARD_SIGNED_IN'		=> 'Signed in',
	'ACP_GROKBOARD_NOT_SIGNED_IN'	=> 'Not signed in. Grok cannot reply until you authenticate.',
	'ACP_GROKBOARD_METHOD'			=> 'Method',
	'ACP_GROKBOARD_METHOD_NONE'		=> '—',
	'ACP_GROKBOARD_METHOD_DEVICE'	=> 'Device code (Grok Build account)',
	'ACP_GROKBOARD_METHOD_KEY'		=> 'API key',
	'ACP_GROKBOARD_ACCOUNT'			=> 'Account',
	'ACP_GROKBOARD_DEVICE'			=> 'Sign in with a device code',
	'ACP_GROKBOARD_DEVICE_EXPLAIN'	=> 'Starts Grok Build device login inside the container. Open the URL on your phone or laptop, enter the code, and wait on this page.',
	'ACP_GROKBOARD_START_DEVICE'	=> 'Start device login',
	'ACP_GROKBOARD_CANCEL_DEVICE'	=> 'Cancel',
	'ACP_GROKBOARD_DEVICE_CANCELLED'=> 'Device login cancelled.',
	'ACP_GROKBOARD_OPEN_URL'		=> 'Open this URL',
	'ACP_GROKBOARD_ENTER_CODE'		=> 'Enter this code',
	'ACP_GROKBOARD_WAITING'			=> 'Waiting for you to finish in the browser…',
	'ACP_GROKBOARD_KEY'				=> 'Or paste an xAI API key',
	'ACP_GROKBOARD_KEY_EXPLAIN'		=> 'Create a key at console.x.ai. It is stored only on this board’s data volume, not in the image.',
	'ACP_GROKBOARD_KEY_SAVED'		=> 'API key saved. Grok can reply.',
	'ACP_GROKBOARD_SAVE_KEY'		=> 'Save API key',
	'ACP_GROKBOARD_CLEAR'			=> 'Sign out / remove credentials',
	'ACP_GROKBOARD_CLEAR_CONFIRM'	=> 'Remove Grok Build credentials from this board? Grok will stop replying until you sign in again.',
	'ACP_GROKBOARD_CLEARED'			=> 'Grok Build credentials removed.',
	'ACP_GROKBOARD_AUTH_FAILED'		=> 'Could not authenticate Grok Build.',
	'ACP_GROKBOARD_NEVER_THREAD'	=> 'Never paste keys or device codes into a forum thread.',
]);
