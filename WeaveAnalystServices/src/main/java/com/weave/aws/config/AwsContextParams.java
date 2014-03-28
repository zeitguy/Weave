package weave.aws.config;

import weave.config.WeaveContextParams;

public class AwsContextParams extends WeaveContextParams
{
	private static String awsConfigPath = "";
	
	public AwsContextParams()
	{
		this.awsConfigPath = this.getConfigPath() + "/../aws-config/";
	}
	
	public static String getAwsConfigPath()
	{
		return awsConfigPath;
	}
}
