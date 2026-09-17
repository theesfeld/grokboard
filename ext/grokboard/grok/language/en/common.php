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
	'GROKBOARD_TYPING'			=> 'Grok is posting…',
	'GROKBOARD_ERROR'			=> 'Grok could not reply: %s',
	'GROKBOARD_NEED_AUTH'		=> 'Grok Build is not signed in, so Grok cannot reply.',
	'GROKBOARD_NEED_AUTH_LINK'	=> 'Administrators: sign in from ACP → Extensions → Grok Board.',
	'GROKBOARD_AUTH_ERROR'		=> 'Grok Build is not signed in. An administrator can authenticate from ACP → Extensions → Grok Board.',
]);
