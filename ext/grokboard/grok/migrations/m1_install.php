<?php

namespace grokboard\grok\migrations;

class m1_install extends \phpbb\db\migration\migration
{
	public function effectively_installed()
	{
		return isset($this->config['grok_user_id']);
	}

	public static function depends_on()
	{
		return ['\phpbb\db\migration\data\v330\v330'];
	}

	public function update_schema()
	{
		return [
			'add_tables' => [
				$this->table_prefix . 'grok_queue' => [
					'COLUMNS' => [
						'queue_id'		=> ['UINT', null, 'auto_increment'],
						'topic_id'		=> ['UINT', 0],
						'forum_id'		=> ['UINT', 0],
						'post_id'		=> ['UINT', 0],
						'user_id'		=> ['UINT', 0],
						'status'		=> ['VCHAR:16', 'pending'],
						'created_time'	=> ['TIMESTAMP', 0],
						'error_text'	=> ['TEXT', ''],
					],
					'PRIMARY_KEY' => 'queue_id',
					'KEYS' => [
						'topic_status' => ['INDEX', ['topic_id', 'status']],
					],
				],
				$this->table_prefix . 'grok_sessions' => [
					'COLUMNS' => [
						'topic_id'		=> ['UINT', 0],
						'session_id'	=> ['VCHAR:80', ''],
						'workspace'		=> ['VCHAR:255', ''],
					],
					'PRIMARY_KEY' => 'topic_id',
				],
			],
		];
	}

	public function revert_schema()
	{
		return [
			'drop_tables' => [
				$this->table_prefix . 'grok_queue',
				$this->table_prefix . 'grok_sessions',
			],
		];
	}

	public function update_data()
	{
		return [
			['config.add', ['grok_user_id', 0]],
			['config.add', ['grok_model', 'grok-build']],
			['config.add', ['grok_enabled', 1]],
		];
	}
}
