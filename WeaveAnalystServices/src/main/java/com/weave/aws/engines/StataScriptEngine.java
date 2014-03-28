package weave.aws.engines;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.OutputStream;

import weave.beans.RResult;

public class StataScriptEngine implements IScriptEngine {

	public class ScriptResult {
		public StataResult[] data;
		public long[] times = new long[2];
	}
	public int runStataScript() throws IOException {

		Runtime run = Runtime.getRuntime();
		Process proc = null;
		proc = run.exec(new String[] { "stata-se", "-q" });
		OutputStream stdin = proc.getOutputStream();
		stdin.write(new String("/Users/franckamayou/Desktop/test.do")
				.getBytes());
		stdin.close();
		BufferedReader stdout = new BufferedReader(new InputStreamReader(
				proc.getInputStream()));
		BufferedReader stderr = new BufferedReader(new InputStreamReader(
				proc.getErrorStream()));

		while (true) {
			String line = null;
			try {
				// check both streams for new data
				if (stdout.ready()) {
					line = stdout.readLine();
				} else if (stderr.ready()) {
					line = stderr.readLine();
				}

				// print out data from stream
				if (line != null) {
					System.out.println(line);
					continue;
				}
			} catch (IOException ioe) {
				// stream error, get the return value of the process and return
				// from this function
				try {
					return proc.exitValue();
				} catch (IllegalThreadStateException itse) {
					return -Integer.MAX_VALUE;
				}
			}
			try {
				// if process finished, return
				return proc.exitValue();
			} catch (IllegalThreadStateException itse) {
				// process is still running, continue
			}
		}

	}

}
