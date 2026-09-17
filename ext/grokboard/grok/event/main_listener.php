<?php

namespace grokboard\grok\event;

use Symfony\Component\EventDispatcher\EventSubscriberInterface;

class main_listener implements EventSubscriberInterface
{
	protected $config;
	protected $db;
	protected $template;
	protected $user;
	protected $helper;
	protected $table_prefix;
	protected $phpbb_root_path;
	protected $php_ext;

	public function __construct(\phpbb\config\config $config, \phpbb\db\driver\driver_interface $db, \phpbb\template\template $template, \phpbb\user $user, \phpbb\controller\helper $helper, $table_prefix, $phpbb_root_path, $php_ext)
	{
		$this->config = $config;
		$this->db = $db;
		$this->template = $template;
		$this->user = $user;
		$this->helper = $helper;
		$this->table_prefix = $table_prefix;
		$this->phpbb_root_path = $phpbb_root_path;
		$this->php_ext = $php_ext;
	}

	public static function getSubscribedEvents()
	{
		return [
			'core.user_setup_after'				=> 'force_login',
			'core.page_header'					=> 'page_header',
			'core.viewtopic_modify_post_data'	=> 'viewtopic_data',
			'core.submit_post_end'				=> 'queue_after_post',
		];
	}

	public function force_login($event)
	{
		if ($this->user->data['user_id'] != ANONYMOUS)
		{
			return;
		}

		if (defined('IN_LOGIN') || defined('ADMIN_START') || defined('IN_CRON') || defined('IN_INSTALL'))
		{
			return;
		}

		$page = $this->user->page['page_name'] ?? '';
		$query = $this->user->page['query_string'] ?? '';

		if ($page === 'ucp.' . $this->php_ext)
		{
			if (preg_match('/mode=(login|logout|confirm)/', $query))
			{
				return;
			}
		}

		if ($page === 'cron.' . $this->php_ext || strpos($query, 'cron') !== false)
		{
			return;
		}

		$login = append_sid($this->phpbb_root_path . 'ucp.' . $this->php_ext, 'mode=login', false, $this->user->session_id);
		redirect($login);
	}

	public function page_header($event)
	{
		if (empty($this->config['grok_enabled']) || $this->user->data['user_id'] == ANONYMOUS)
		{
			return;
		}

		$hash = generate_link_hash('grok_stream');
		$this->template->assign_vars([
			'S_GROKBOARD'			=> true,
			'GROKBOARD_USER_ID'		=> (int) $this->config['grok_user_id'],
			'U_GROKBOARD_STREAM'		=> $this->helper->route('grokboard_stream', ['hash' => $hash]),
		]);
	}

	public function viewtopic_data($event)
	{
		$topic_data = $event['topic_data'];
		$topic_id = (int) $topic_data['topic_id'];

		$sql = 'SELECT queue_id, post_id, status
			FROM ' . $this->table_prefix . 'grok_queue
			WHERE topic_id = ' . $topic_id . "
				AND status IN ('pending', 'running')
			ORDER BY queue_id DESC";
		$result = $this->db->sql_query_limit($sql, 1);
		$row = $this->db->sql_fetchrow($result);
		$this->db->sql_freeresult($result);

		$this->template->assign_vars([
			'GROKBOARD_TOPIC_ID'		=> $topic_id,
			'GROKBOARD_FORUM_ID'		=> (int) $topic_data['forum_id'],
			'GROKBOARD_PENDING'		=> $row ? 1 : 0,
			'GROKBOARD_QUEUE_ID'		=> $row ? (int) $row['queue_id'] : 0,
			'GROKBOARD_POST_ID'		=> $row ? (int) $row['post_id'] : 0,
			'GROKBOARD_LAST_POSTER'	=> (int) $topic_data['topic_last_poster_id'],
		]);
	}

	public function queue_after_post($event)
	{
		if (empty($this->config['grok_enabled']))
		{
			return;
		}

		$data = $event['data'];
		$mode = $event['mode'];
		$grok_id = (int) $this->config['grok_user_id'];
		$poster_id = (int) $this->user->data['user_id'];

		if (!$grok_id || $poster_id === $grok_id || $poster_id == ANONYMOUS)
		{
			return;
		}

		if (!in_array($mode, ['post', 'reply', 'quote'], true))
		{
			return;
		}

		$sql = 'INSERT INTO ' . $this->table_prefix . 'grok_queue ' . $this->db->sql_build_array('INSERT', [
			'topic_id'		=> (int) $data['topic_id'],
			'forum_id'		=> (int) $data['forum_id'],
			'post_id'		=> (int) $data['post_id'],
			'user_id'		=> $poster_id,
			'status'		=> 'pending',
			'created_time'	=> time(),
			'error_text'	=> '',
		]);
		$this->db->sql_query($sql);
	}
}
