<?php

namespace grokboard\grok\auth;

class cli
{
	const BIN = '/usr/local/sbin/grokboard-auth';

	public function status()
	{
		return $this->run(['status'], '', 8);
	}

	public function set_key($key)
	{
		return $this->run(['set-key'], (string) $key, 8);
	}

	public function device_start()
	{
		return $this->run(['device-start'], '', 20);
	}

	public function device_status()
	{
		return $this->run(['device-status'], '', 8);
	}

	public function device_cancel()
	{
		return $this->run(['device-cancel'], '', 8);
	}

	public function clear()
	{
		return $this->run(['clear'], '', 8);
	}

	public function signed_in()
	{
		$stamp = @file_get_contents('/etc/grokboard/auth.status');
		if (is_string($stamp) && preg_match('/^ok\b/m', $stamp))
		{
			return true;
		}
		$st = $this->status();
		return !empty($st['authenticated']);
	}

	protected function run(array $args, $stdin, $timeout)
	{
		if (!is_executable(self::BIN))
		{
			return ['ok' => false, 'authenticated' => false, 'error' => 'grokboard-auth helper missing'];
		}

		$cmd = array_merge(['timeout', (string) $timeout, 'sudo', '-n', self::BIN], $args);
		$proc = proc_open($cmd, [
			0 => ['pipe', 'r'],
			1 => ['pipe', 'w'],
			2 => ['pipe', 'w'],
		], $pipes, null, [
			'PATH'	=> '/usr/local/sbin:/usr/local/bin:/usr/bin:/bin',
			'LANG'	=> 'C.UTF-8',
		]);
		if (!is_resource($proc))
		{
			return ['ok' => false, 'authenticated' => false, 'error' => 'could not start grokboard-auth'];
		}

		if ($stdin !== '')
		{
			fwrite($pipes[0], $stdin);
			if (substr($stdin, -1) !== "\n")
			{
				fwrite($pipes[0], "\n");
			}
		}
		fclose($pipes[0]);
		$out = stream_get_contents($pipes[1]);
		$err = stream_get_contents($pipes[2]);
		fclose($pipes[1]);
		fclose($pipes[2]);
		proc_close($proc);

		$json = json_decode((string) $out, true);
		if (!is_array($json))
		{
			$msg = trim($err) !== '' ? trim($err) : trim((string) $out);
			return ['ok' => false, 'authenticated' => false, 'error' => $msg !== '' ? $msg : 'auth helper returned no JSON'];
		}
		return $json;
	}
}
