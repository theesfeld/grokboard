<?php

namespace grokboard\grok\migrations;

class m2_acp_module extends \phpbb\db\migration\migration
{
	public function effectively_installed()
	{
		$sql = 'SELECT module_id FROM ' . $this->table_prefix . "modules
			WHERE module_langname = 'ACP_GROKBOARD_AUTH'";
		$result = $this->db->sql_query_limit($sql, 1);
		$row = $this->db->sql_fetchrow($result);
		$this->db->sql_freeresult($result);
		return (bool) $row;
	}

	public static function depends_on()
	{
		return ['\grokboard\grok\migrations\m1_install'];
	}

	public function update_data()
	{
		return [
			['module.add', [
				'acp',
				'ACP_CAT_DOT_MODS',
				'ACP_GROKBOARD',
			]],
			['module.add', [
				'acp',
				'ACP_GROKBOARD',
				[
					'module_basename'	=> '\grokboard\grok\acp\main_module',
					'modes'				=> ['auth'],
				],
			]],
		];
	}
}
