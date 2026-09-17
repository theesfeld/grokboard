<?php

namespace grokboard\grok\acp;

class main_info
{
	public function module()
	{
		return [
			'filename'	=> '\grokboard\grok\acp\main_module',
			'title'		=> 'ACP_GROKBOARD',
			'modes'		=> [
				'auth'	=> [
					'title'	=> 'ACP_GROKBOARD_AUTH',
					'auth'	=> 'ext_grokboard/grok && acl_a_board',
					'cat'	=> ['ACP_GROKBOARD'],
				],
			],
		];
	}
}
