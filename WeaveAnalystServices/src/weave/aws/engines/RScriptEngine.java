package weave.aws.engines;

import java.rmi.RemoteException;
import java.util.Vector;

import org.rosuda.REngine.REXP;
import org.rosuda.REngine.Rserve.RConnection;

import weave.aws.servlets.DataService;
import weave.aws.utils.AWSUtils;
import weave.servlets.RService;
import weave.servlets.RServiceUsingRserve;

import weave.beans.RResult;
import weave.utils.SQLUtils.WhereClause.NestedColumnFilters;

public class RScriptEngine extends RService implements IScriptEngine
{

	public class ScriptResult {
		public RResult[] data;
		public long[] times = new long[2];
	}
	  
    // this functions intends to run a script with filtered.
	// essentially this function should eventually be our main run script function.
	// in the request object, there will be: the script name
	// and the columns, along with their filters.
	// TODO not completed
	public ScriptResult runScriptWithFilteredColumns(String scriptName,	int [] ids, NestedColumnFilters filters) throws Exception
	{
		RResult[] returnedColumns;

		String cannedScript = awsConfigPath + "RScripts/" + scriptName;
		
		long startTime = System.currentTimeMillis();
		
		Object[][] recordData = DataService.getFilteredRows(ids, filters, null).recordData;
		if(recordData.length == 0){
			throw new RemoteException("Query produced no rows...");
		}
		Object[][] columnData = AWSUtils.transpose(recordData);
		recordData = null;
		
		long endTime = System.currentTimeMillis();
		
		long time1 = endTime - startTime;
		
		Object[] inputValues = {cannedScript, columnData};
		String[] inputNames = {"cannedScriptPath", "dataset"};

		String finalScript = "scriptFromFile <- source(cannedScriptPath)\n" +
					         "scriptFromFile$value(dataset)"; 

		String[] outputNames = {};
		
		startTime = System.currentTimeMillis();
		returnedColumns = runScript(null, inputNames, inputValues, outputNames, finalScript, "", false, false);
		endTime = System.currentTimeMillis();
		columnData = null;
		long time2 = endTime - startTime;
		
		ScriptResult result = new ScriptResult();
		
		result.data = returnedColumns;
		result.times[0] = time1;
		result.times[1] = time2;
		
		return result;

	}
	
	public static RResult[] runScript(String docrootPath, String[] inputNames, Object[] inputValues, String[] outputNames, String script, String plotScript, boolean showIntermediateResults, boolean showWarnings) throws Exception
	{		
		RConnection rConnection = RServiceUsingRserve.getRConnection();
		
		RResult[] results = null;
		Vector<RResult> resultVector = new Vector<RResult>();
		try
		{
			// ASSIGNS inputNames to respective Vector in R "like x<-c(1,2,3,4)"			
			RServiceUsingRserve.assignNamesToVector(rConnection,inputNames,inputValues);
			
			evaluateWithTypeChecking( rConnection, script, resultVector, showIntermediateResults, showWarnings);
			
			if (plotScript != ""){// R Script to EVALUATE plotScript
				String plotEvalValue = RServiceUsingRserve.plotEvalScript(rConnection,docrootPath, plotScript, showWarnings);
				resultVector.add(new RResult("Plot Results", plotEvalValue));
			}
			for (int i = 0; i < outputNames.length; i++){// R Script to EVALUATE output Script
				String name = outputNames[i];						
				REXP evalValue = evalScript( rConnection, name, showWarnings);	
				resultVector.add(new RResult(name, RServiceUsingRserve.rexp2javaObj(evalValue)));					
			}
			// clear R objects
			clearCacheTimeLog = true;
			evalScript( rConnection, "rm(list=ls())", false);
			
		}
		catch (Exception e)	{
			e.printStackTrace();
			System.out.println("printing error");
			System.out.println(e.getMessage());
			throw new RemoteException("Unable to run script", e);
		}
		finally
		{
			results = new RResult[resultVector.size()];
			resultVector.toArray(results);
			rConnection.close();
		}
		return results;
	}
}
