<?php

namespace grokboard\grok\controller;

class stream
{
	protected $auth;
	protected $config;
	protected $db;
	protected $request;
	protected $user;
	protected $phpbb_root_path;
	protected $php_ext;
	protected $table_prefix;

	public function __construct(\phpbb\auth\auth $auth, \phpbb\config\config $config, \phpbb\db\driver\driver_interface $db, \phpbb\request\request $request, \phpbb\user $user, $phpbb_root_path, $php_ext, $table_prefix)
	{
		$this->auth = $auth;
		$this->config = $config;
		$this->db = $db;
		$this->request = $request;
		$this->user = $user;
		$this->phpbb_root_path = $phpbb_root_path;
		$this->php_ext = $php_ext;
		$this->table_prefix = $table_prefix;
	}

	public function handle()
	{
		$this->user->add_lang_ext('grokboard/grok', 'common');

		if ($this->user->data['user_id'] == ANONYMOUS)
		{
			return $this->fail(403, 'NOT_AUTHORISED');
		}

		$hash = $this->request->variable('hash', '');
		if (!check_link_hash($hash, 'grok_stream'))
		{
			return $this->fail(403, 'NOT_AUTHORISED');
		}

		$queue_id = $this->request->variable('queue_id', 0);
		$topic_id = $this->request->variable('t', 0);

		if (!$queue_id && $topic_id)
		{
			$sql = 'SELECT queue_id FROM ' . $this->table_prefix . 'grok_queue
				WHERE topic_id = ' . (int) $topic_id . "
					AND status = 'pending'
				ORDER BY queue_id DESC";
			$result = $this->db->sql_query_limit($sql, 1);
			$row = $this->db->sql_fetchrow($result);
			$this->db->sql_freeresult($result);
			$queue_id = $row ? (int) $row['queue_id'] : 0;
		}

		if (!$queue_id)
		{
			return $this->fail(404, 'NO_QUEUE');
		}

		$sql = 'SELECT * FROM ' . $this->table_prefix . 'grok_queue WHERE queue_id = ' . (int) $queue_id;
		$result = $this->db->sql_query($sql);
		$queue = $this->db->sql_fetchrow($result);
		$this->db->sql_freeresult($result);

		if (!$queue || !in_array($queue['status'], ['pending', 'running'], true))
		{
			return $this->fail(409, 'QUEUE_DONE');
		}

		$grok_id = (int) $this->config['grok_user_id'];
		if (!$grok_id)
		{
			return $this->fail(500, 'NO_GROK_USER');
		}

		$this->db->sql_query('UPDATE ' . $this->table_prefix . "grok_queue SET status = 'running' WHERE queue_id = " . (int) $queue_id);

		$this->sse_headers();

		$full = '';
		$session_id = '';
		$error = $this->run_grok_cli((int) $queue['topic_id'], (int) $queue['forum_id'], (int) $queue['post_id'], $full, $session_id);

		if ($error !== '' || trim($full) === '')
		{
			$error = $error ?: 'empty reply from grok -p';
			$this->db->sql_query('UPDATE ' . $this->table_prefix . 'grok_queue SET ' . $this->db->sql_build_array('UPDATE', [
				'status'		=> 'error',
				'error_text'	=> $error,
			]) . ' WHERE queue_id = ' . (int) $queue_id);
			$this->sse('error', ['message' => $error]);
			$this->sse_end();
			exit;
		}

		if ($session_id !== '')
		{
			$this->save_session((int) $queue['topic_id'], $session_id, $this->workspace_path((int) $queue['forum_id'], (int) $queue['topic_id']));
		}

		$post_id = $this->insert_grok_post($queue, $grok_id, $full);

		$this->db->sql_query('UPDATE ' . $this->table_prefix . 'grok_queue SET ' . $this->db->sql_build_array('UPDATE', [
			'status'		=> 'done',
			'error_text'	=> '',
		]) . ' WHERE queue_id = ' . (int) $queue_id);

		$this->sse('done', [
			'post_id'	=> $post_id,
			'html'		=> $this->display_html($full),
		]);
		$this->sse_end();
		exit;
	}

	protected function insert_grok_post(array $queue, $grok_id, $message)
	{
		include_once $this->phpbb_root_path . 'includes/functions_posting.' . $this->php_ext;
		include_once $this->phpbb_root_path . 'includes/functions_user.' . $this->php_ext;
		include_once $this->phpbb_root_path . 'includes/functions_content.' . $this->php_ext;

		$sql = 'SELECT * FROM ' . USERS_TABLE . ' WHERE user_id = ' . (int) $grok_id;
		$result = $this->db->sql_query($sql);
		$grok = $this->db->sql_fetchrow($result);
		$this->db->sql_freeresult($result);
		if (!$grok)
		{
			throw new \RuntimeException('Grok user missing');
		}

		$saved_user = $this->user->data;
		$saved_auth = $this->auth;
		$this->user->data = array_merge($this->user->data, $grok);
		$this->auth->acl($this->user->data);

		$sql = 'SELECT topic_title, forum_id FROM ' . TOPICS_TABLE . ' WHERE topic_id = ' . (int) $queue['topic_id'];
		$result = $this->db->sql_query($sql);
		$topic = $this->db->sql_fetchrow($result);
		$this->db->sql_freeresult($result);

		$uid = $bitfield = $flags = '';
		$text = $message;
		generate_text_for_storage($text, $uid, $bitfield, $flags, true, true, true);

		$poll = [];
		$data = [
			'forum_id'				=> (int) $queue['forum_id'] ?: (int) $topic['forum_id'],
			'topic_id'				=> (int) $queue['topic_id'],
			'icon_id'				=> 0,
			'enable_bbcode'			=> true,
			'enable_smilies'		=> true,
			'enable_urls'			=> true,
			'enable_sig'			=> false,
			'message'				=> $text,
			'message_md5'			=> md5($text),
			'bbcode_bitfield'		=> $bitfield,
			'bbcode_uid'			=> $uid,
			'bbcode_flags'			=> $flags,
			'poster_ip'				=> '127.0.0.1',
			'post_edit_locked'		=> 0,
			'enable_indexing'		=> true,
			'notify_set'			=> false,
			'notify'				=> false,
			'post_time'				=> time(),
			'forum_name'			=> '',
			'force_approved_state'	=> true,
			'topic_title'			=> $topic['topic_title'],
		];

		$subject = 'Re: ' . censor_text($topic['topic_title']);
		submit_post('reply', $subject, $grok['username'], POST_NORMAL, $poll, $data);

		$this->user->data = $saved_user;
		$this->auth->acl($this->user->data);

		return (int) $data['post_id'];
	}

	protected function run_grok_cli($topic_id, $forum_id, $post_id, &$full, &$session_id)
	{
		$workspace = $this->workspace_path($forum_id, $topic_id);
		$wrapper = '/usr/local/sbin/grok-phpbb';
		if (!is_executable($wrapper))
		{
			return 'grok-phpbb wrapper missing';
		}

		$prompt = $this->topic_prompt($topic_id, $forum_id, $post_id);
		$prompt_file = '/home/grokbuild/tmp/prompt-' . (int) $topic_id . '-' . (int) $post_id . '.txt';
		if (@file_put_contents($prompt_file, $prompt) === false)
		{
			return 'could not write prompt file';
		}
		@chmod($prompt_file, 0664);

		$cmd = [
			'sudo', '-n', '-u', 'grokbuild', $wrapper, $workspace,
			'--prompt-file', $prompt_file,
		];
		$existing = $this->load_session($topic_id);
		if ($existing !== '')
		{
			$cmd[] = '--resume';
			$cmd[] = $existing;
		}

		$descriptors = [
			0 => ['pipe', 'r'],
			1 => ['pipe', 'w'],
			2 => ['pipe', 'w'],
		];
		$proc = proc_open($cmd, $descriptors, $pipes, null, [
			'PATH'		=> '/usr/local/bin:/usr/bin:/bin',
			'HOME'		=> '/home/grokbuild',
			'LANG'		=> 'C.UTF-8',
		]);
		if (!is_resource($proc))
		{
			return 'proc_open failed';
		}
		fclose($pipes[0]);
		stream_set_blocking($pipes[1], false);
		stream_set_blocking($pipes[2], false);

		$buf = '';
		$err = '';
		$full = '';
		$session_id = $existing;
		$end = time() + 3600;
		while (time() < $end)
		{
			$read = [$pipes[1], $pipes[2]];
			$write = $except = null;
			@stream_select($read, $write, $except, 1);
			foreach ($read as $pipe)
			{
				$chunk = fread($pipe, 8192);
				if ($chunk === false || $chunk === '')
				{
					continue;
				}
				if ($pipe === $pipes[2])
				{
					$err .= $chunk;
					continue;
				}
				$buf .= $chunk;
				while (($nl = strpos($buf, "\n")) !== false)
				{
					$line = trim(substr($buf, 0, $nl));
					$buf = substr($buf, $nl + 1);
					if ($line === '')
					{
						continue;
					}
					$ev = json_decode($line, true);
					if (!is_array($ev))
					{
						continue;
					}
					$type = $ev['type'] ?? '';
					if ($type === 'text' && isset($ev['data']) && $ev['data'] !== '')
					{
						$full .= $ev['data'];
						$this->sse('token', ['t' => $ev['data']]);
					}
					else if ($type === 'tool_call')
					{
						$name = $ev['toolName'] ?? $ev['title'] ?? 'tool';
						$this->sse('tool', ['name' => $name, 'status' => $ev['status'] ?? 'running']);
					}
					else if ($type === 'end')
					{
						if (!empty($ev['sessionId']))
						{
							$session_id = $ev['sessionId'];
						}
						if (isset($ev['text']) && $full === '' && $ev['text'] !== '')
						{
							$full = $ev['text'];
							$this->sse('token', ['t' => $ev['text']]);
						}
					}
					else if ($type === 'error')
					{
						$err .= ($ev['message'] ?? 'grok error') . "\n";
					}
				}
			}
			$status = proc_get_status($proc);
			if (!$status['running'] && feof($pipes[1]) && feof($pipes[2]))
			{
				break;
			}
		}
		fclose($pipes[1]);
		fclose($pipes[2]);
		$code = proc_close($proc);
		@unlink($prompt_file);

		if (trim($full) === '')
		{
			return trim($err) !== '' ? trim($err) : ('grok -p exit ' . $code);
		}
		return '';
	}

	protected function workspace_path($forum_id, $topic_id)
	{
		return '/home/grokbuild/workspace/' . $this->forum_slug($forum_id) . '/t-' . (int) $topic_id;
	}

	protected function forum_slug($forum_id)
	{
		$sql = 'SELECT forum_name FROM ' . FORUMS_TABLE . ' WHERE forum_id = ' . (int) $forum_id;
		$result = $this->db->sql_query($sql);
		$name = (string) $this->db->sql_fetchfield('forum_name');
		$this->db->sql_freeresult($result);
		$slug = strtolower($name);
		$slug = preg_replace('/[^a-z0-9]+/', '-', $slug);
		$slug = trim($slug, '-');
		return $slug !== '' ? $slug : 'forum-' . (int) $forum_id;
	}

	protected function topic_prompt($topic_id, $forum_id, $post_id)
	{
		$sql = 'SELECT p.post_text, p.bbcode_uid, u.username
			FROM ' . POSTS_TABLE . ' p
			JOIN ' . USERS_TABLE . ' u ON u.user_id = p.poster_id
			WHERE p.post_id = ' . (int) $post_id;
		$result = $this->db->sql_query($sql);
		$row = $this->db->sql_fetchrow($result);
		$this->db->sql_freeresult($result);
		$text = $row ? $this->plain($row['post_text'], $row['bbcode_uid']) : '';
		$who = $row['username'] ?? 'a member';

		$sql = 'SELECT forum_name, forum_desc FROM ' . FORUMS_TABLE . ' WHERE forum_id = ' . (int) $forum_id;
		$result = $this->db->sql_query($sql);
		$forum = $this->db->sql_fetchrow($result);
		$this->db->sql_freeresult($result);
		$forum_name = $forum['forum_name'] ?? 'Board';

		$sql = 'SELECT topic_title FROM ' . TOPICS_TABLE . ' WHERE topic_id = ' . (int) $topic_id;
		$result = $this->db->sql_query($sql);
		$title = (string) $this->db->sql_fetchfield('topic_title');
		$this->db->sql_freeresult($result);

		return "Post in this phpBB thread as Grok. Follow your phpBB board rules "
			. "(BBCode and smilies, never Markdown).\n\n"
			. "Forum: {$forum_name}\n"
			. "Thread: {$title}\n"
			. "Stay in this thread's project directory.\n\n"
			. $who . " wrote:\n" . $text . "\n";
	}

	protected function load_session($topic_id)
	{
		$sql = 'SELECT session_id FROM ' . $this->table_prefix . 'grok_sessions WHERE topic_id = ' . (int) $topic_id;
		$result = $this->db->sql_query($sql);
		$row = $this->db->sql_fetchrow($result);
		$this->db->sql_freeresult($result);
		return $row ? (string) $row['session_id'] : '';
	}

	protected function save_session($topic_id, $session_id, $workspace)
	{
		$sql = 'SELECT topic_id FROM ' . $this->table_prefix . 'grok_sessions WHERE topic_id = ' . (int) $topic_id;
		$result = $this->db->sql_query($sql);
		$exists = (bool) $this->db->sql_fetchrow($result);
		$this->db->sql_freeresult($result);
		if ($exists)
		{
			$this->db->sql_query('UPDATE ' . $this->table_prefix . 'grok_sessions SET ' . $this->db->sql_build_array('UPDATE', [
				'session_id'	=> $session_id,
				'workspace'		=> $workspace,
			]) . ' WHERE topic_id = ' . (int) $topic_id);
			return;
		}
		$this->db->sql_query('INSERT INTO ' . $this->table_prefix . 'grok_sessions ' . $this->db->sql_build_array('INSERT', [
			'topic_id'		=> (int) $topic_id,
			'session_id'	=> $session_id,
			'workspace'		=> $workspace,
		]));
	}

	protected function plain($text, $uid)
	{
		$text = str_replace(':' . $uid, '', $text);
		$text = preg_replace('#\[/?[^\]]+\]#', '', $text);
		$text = html_entity_decode(strip_tags($text), ENT_QUOTES, 'UTF-8');
		return trim($text);
	}

	protected function display_html($bbcode)
	{
		include_once $this->phpbb_root_path . 'includes/functions_content.' . $this->php_ext;
		$uid = $bitfield = $flags = '';
		$text = $bbcode;
		generate_text_for_storage($text, $uid, $bitfield, $flags, true, true, true);
		return generate_text_for_display($text, $uid, $bitfield, $flags);
	}

	protected function api_key()
	{
		$paths = ['/etc/grokboard/xai.env', '/etc/grokboard/xai_api_key'];
		foreach ($paths as $path)
		{
			if (!is_readable($path))
			{
				continue;
			}
			$raw = file_get_contents($path);
			if (strpos($path, '.env') !== false)
			{
				foreach (explode("\n", $raw) as $line)
				{
					if (strpos($line, 'XAI_API_KEY=') === 0)
					{
						return trim(substr($line, 12), " \t\"'");
					}
				}
			}
			else
			{
				$key = trim($raw);
				if ($key !== '')
				{
					return $key;
				}
			}
		}
		$env = getenv('XAI_API_KEY');
		return $env !== false ? $env : '';
	}

	protected function sse_headers()
	{
		@ini_set('output_buffering', 'off');
		@ini_set('zlib.output_compression', 0);
		while (ob_get_level())
		{
			ob_end_flush();
		}
		header('Content-Type: text/event-stream');
		header('Cache-Control: no-cache');
		header('Connection: keep-alive');
		header('X-Accel-Buffering: no');
	}

	protected function sse($event, array $data)
	{
		echo 'event: ' . $event . "\n";
		echo 'data: ' . json_encode($data, JSON_UNESCAPED_UNICODE) . "\n\n";
		@ob_flush();
		@flush();
	}

	protected function sse_end()
	{
		echo "event: close\ndata: {}\n\n";
		@ob_flush();
		@flush();
	}

	protected function fail($code, $msg)
	{
		throw new \phpbb\exception\http_exception($code, $msg);
	}
}
