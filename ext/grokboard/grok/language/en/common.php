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
	'GROKBOARD_TYPING'	=> 'Grok is posting…',
	'GROKBOARD_ERROR'	=> 'Grok could not reply: %s',
]);
