/*
    Weave (Web-based Analysis and Visualization Environment)
    Copyright (C) 2008-2011 University of Massachusetts Lowell

    This file is a part of Weave.

    Weave is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License, Version 3,
    as published by the Free Software Foundation.

    Weave is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with Weave.  If not, see <http://www.gnu.org/licenses/>.
*/

package weave.servlets;

import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.PrintWriter;
import java.lang.reflect.Array;
import java.lang.reflect.Field;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;
import java.lang.reflect.Type;
import java.lang.reflect.TypeVariable;
import java.rmi.RemoteException;
import java.util.Arrays;
import java.util.Collection;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Vector;
import java.util.zip.DeflaterOutputStream;

import javax.servlet.ServletException;
import javax.servlet.ServletOutputStream;
import javax.servlet.http.HttpServlet;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;

import org.apache.commons.io.IOUtils;
import org.postgresql.util.Base64;

import weave.beans.JsonRpcErrorModel;
import weave.beans.JsonRpcRequestModel;
import weave.beans.JsonRpcResponseModel;
import weave.utils.CSVParser;
import weave.utils.ListUtils;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonDeserializationContext;
import com.google.gson.JsonDeserializer;
import com.google.gson.JsonElement;
import com.google.gson.JsonNull;
import com.google.gson.JsonParseException;
import com.google.gson.JsonPrimitive;
import com.google.gson.JsonSerializationContext;
import com.google.gson.JsonSerializer;
import com.heatonresearch.httprecipes.html.PeekableInputStream;
import com.thoughtworks.paranamer.BytecodeReadingParanamer;
import com.thoughtworks.paranamer.Paranamer;

import flex.messaging.MessageException;
import flex.messaging.io.SerializationContext;
import flex.messaging.io.amf.ASObject;
import flex.messaging.io.amf.Amf3Input;
import flex.messaging.io.amf.Amf3Output;
import flex.messaging.messages.ErrorMessage;

/**
 * This class provides a servlet interface to a set of functions.
 * The functions may be invoked using URL parameters via HTTP GET using url parameters
 * or via HTTP POST using JSON RPC 2.0 or AMF3-serialized objects.
 * If using URL variables or JSON RPC 2.0, the return value will be provided as a JSON RPC 2.0 response object.
 * If using AMF3, the return value will be provided as compressed AMF3.
 * 
 * @author skota
 * @author adufilie
 * @author skolman
 */

public class WeaveServlet extends HttpServlet
{
	private static final long serialVersionUID = 1L;
	public static long debugThreshold = 1000;
	
	/**
	 * This is the name of the URL parameter corresponding to the method name.
	 */
	protected final String METHOD = "method";
	protected final String PARAMS = "params";
	protected final String STREAM_PARAMETER_INDEX = "streamParameterIndex";
	
	private Map<String, ExposedMethod> methodMap = new HashMap<String, ExposedMethod>(); //Key: methodName
    private Paranamer paranamer = new BytecodeReadingParanamer(); // this gets parameter names from Methods
    
    /**
     * This class contains a Method with its parameter names and class instance.
     */
	private class ExposedMethod
	{
		public ExposedMethod(Object instance, Method method, String[] paramNames)
		{
			this.instance = instance;
			this.method = method;
			this.paramNames = paramNames;
		}
		public Object instance;
		public Method method;
		public String[] paramNames;
	}
	
	/**
	 * Default constructor.
	 * This initializes all public methods defined in a class extending WeaveServlet.
	 */
	protected WeaveServlet()
	{
		super();
		initLocalMethods();
	}
	
	/**
	 * @param serviceObjects The objects to invoke methods on.
	 */
	protected WeaveServlet(Object ...serviceObjects)
	{
	    super();
	    initLocalMethods();
	    for (Object serviceObject : serviceObjects)
	    	initAllMethods(serviceObject);
	}
	
	/**
	 * This function will expose all the public methods of this object as servlet methods.
	 */
	protected void initLocalMethods()
	{
		initAllMethods(this);
	}
	
	/**
	 * This function will expose all the declared public methods of a class as servlet methods,
	 * except methods that match those declared by WeaveServlet or a superclass of WeaveServlet.
	 * @param serviceObject The object containing public methods to be exposed by the servlet.
	 */
	protected void initAllMethods(Object serviceObject)
	{
		Method[] weaveServletMethods = WeaveServlet.class.getMethods();
		Method[] declaredMethods = serviceObject.getClass().getDeclaredMethods();
		for (int i = declaredMethods.length; i-- > 0;)
		{
			Method declaredMethod = declaredMethods[i];
			boolean shouldIgnore = false;
			for (Method weaveServletMethod : weaveServletMethods)
			{
				if (declaredMethod.getName().equals(weaveServletMethod.getName()) &&
					Arrays.equals(declaredMethod.getParameterTypes(), weaveServletMethod.getParameterTypes()) )
				{
					shouldIgnore = true;
					break;
				}
			}
			if (!shouldIgnore)
				initMethod(serviceObject, declaredMethod);
		}
		
		// for debugging
		printExposedMethods();
	}
    
    /**
     * @param serviceObject The instance of an object to use in the servlet.
     * @param method The method to expose on serviceObject.
     */
    synchronized protected void initMethod(Object serviceObject, Method method)
    {
    	// only expose public methods
    	if (!Modifier.isPublic(method.getModifiers()))
    		return;
		String methodName = method.getName();
		if (methodMap.containsKey(methodName))
    	{
			methodMap.put(methodName, null);

			System.err.println(String.format(
    				"Method %s.%s will not be supported because there are multiple definitions.",
    				this.getClass().getName(), methodName
    			));
    	}
		else
		{
			String[] paramNames = null;
			paramNames = paranamer.lookupParameterNames(method, false); // returns null if not found
			
			methodMap.put(methodName, new ExposedMethod(serviceObject, method, paramNames));
		}
    }
    
    protected void printExposedMethods()
    {
    	String output = "";
    	List<String> methodNames = new Vector<String>(methodMap.keySet());
    	Collections.sort(methodNames);
    	for (String methodName : methodNames)
    	{
    		ExposedMethod m = methodMap.get(methodName);
    		if (m != null)
    		{
    			if (m.method.getAnnotation(Deprecated.class) != null)
    				continue;
    			output += String.format(
	    				"Exposed servlet method: %s.%s\n",
	    				m.instance.getClass().getName(),
	    				formatFunctionSignature(
	    						m.method.getName(),
	    						m.method.getParameterTypes(),
	    						m.paramNames
	    					)
	    			);
    		}
    		else
    			output += "Not exposed: "+methodName;
    	}
    	System.out.print(output);
    }
    
    private static class ServletRequestInfo
    {
    	public ServletRequestInfo(HttpServletRequest request, HttpServletResponse response) throws IOException
    	{
    		this.request = request;
    		this.response = response;
    		this.inputStream = new PeekableInputStream(request.getInputStream());
    	}
    	
    	private ServletOutputStream _servletOutputStream = null;
    	public ServletOutputStream getOutputStream() throws IOException
    	{
    		if (_servletOutputStream == null)
    			_servletOutputStream = response.getOutputStream();
    		return _servletOutputStream;
    	}
    	
    	@SuppressWarnings("unused")
		public HttpServletRequest request;
    	public HttpServletResponse response;
    	public JsonRpcRequestModel currentJsonRequest;
    	public List<JsonRpcResponseModel> jsonResponses = new Vector<JsonRpcResponseModel>();
    	public Number streamParameterIndex = null;
    	public PeekableInputStream inputStream;
    	public Boolean isBatchRequest = false;
    }
    
    /**
     * This maps a thread to the corresponding RequestInfo for the doGet() or doPost() call that thread is handling.
     */
    private Map<Thread,ServletRequestInfo> _servletRequestInfo = new HashMap<Thread,ServletRequestInfo>();
    
    /**
     * This function retrieves the ServletOutputStream associated with the current thread's doGet() or doPost() call.
     * In a public function with a void return type, you can use the ServletOutputStream for full control over the output.
     */
    protected ServletOutputStream getServletOutputStream() throws IOException
    {
    	return getServletRequestInfo().getOutputStream();
    }
    
    private ServletRequestInfo getServletRequestInfo()
    {
    	synchronized (_servletRequestInfo)
    	{
    		return _servletRequestInfo.get(Thread.currentThread());
    	}
    }
    
    private ServletRequestInfo setServletRequestInfo(HttpServletRequest request, HttpServletResponse response) throws IOException
    {
    	synchronized (_servletRequestInfo)
    	{
    		ServletRequestInfo info = new ServletRequestInfo(request, response);
    		_servletRequestInfo.put(Thread.currentThread(), info);
    		return info;
    	}
    }
    
    private void removeServletRequestInfo()
    {
		synchronized (_servletRequestInfo)
		{
			_servletRequestInfo.remove(Thread.currentThread());
		}
    }
    
    protected void doPost(HttpServletRequest request, HttpServletResponse response) throws ServletException, IOException
    {
    	handleServletRequest(request, response);
    }
    
    protected void doGet(HttpServletRequest request, HttpServletResponse response) throws ServletException, IOException
    {
    	handleServletRequest(request, response);
    }

    @SuppressWarnings("unchecked")
	private void handleServletRequest(HttpServletRequest request, HttpServletResponse response) throws IOException, ServletException
    {
    	try
    	{
    		ServletRequestInfo info = setServletRequestInfo(request, response);
    		
    		if (request.getMethod().equals("GET"))
    		{
        		List<String> urlParamNames = Collections.list(request.getParameterNames());
        		
    			HashMap<String, String> params = new HashMap<String,String>();
    			
    			for (String paramName : urlParamNames)
    				params.put(paramName, request.getParameter(paramName));
    			JsonRpcRequestModel json = new JsonRpcRequestModel();
    			json.jsonrpc = JSONRPC_VERSION;
    			json.id = "";
    			json.method = params.remove(METHOD);
    			json.params = params;
    			
	    		info.currentJsonRequest = json;
	    		invokeMethod(json.method, params);
    		}
    		else // post
    		{
	    		try
	    		{
	    			String methodName;
	    			Object methodParams;
	    			if (info.inputStream.peek() == '[' || info.inputStream.peek() == '{') // json
	    			{
	    				handleArrayOfJsonRequests(info.inputStream,response);
	    			}
	    			else // AMF3
	    			{
	    				ASObject obj = (ASObject)deserializeAmf3(info.inputStream);
	    				methodName = (String) obj.get(METHOD);
	    				methodParams = obj.get(PARAMS);
	    				info.streamParameterIndex = (Number) obj.get(STREAM_PARAMETER_INDEX);
	    				invokeMethod(methodName, methodParams);
	    			}
		    	}
	    		catch (IOException e)
	    		{
	    			sendError(e, null);
	    		}
	    		catch (Exception e)
		    	{
		    		sendError(e, null);
		    	}
		    	
    		}
    		handleJsonResponses();
    	}
    	finally
    	{
    		removeServletRequestInfo();
    	}
	}
	
	public static final String JSONRPC_VERSION = "2.0";
	
	private static final Gson GSON = new GsonBuilder()
		.registerTypeHierarchyAdapter(byte[].class, new ByteArrayToBase64TypeAdapter())
		.registerTypeHierarchyAdapter(Double.class, new NaNToNullAdapter())
		.disableHtmlEscaping()
		.create();
	
	// Base64 adapter modified from GsonHelper.java, https://gist.github.com/orip/3635246
	private static class ByteArrayToBase64TypeAdapter implements JsonSerializer<byte[]>, JsonDeserializer<byte[]>
	{
		public byte[] deserialize(JsonElement json, Type typeOfT, JsonDeserializationContext context) throws JsonParseException
		{
			return Base64.decode(json.getAsString());
		}
		public JsonElement serialize(byte[] src, Type typeOfSrc, JsonSerializationContext context)
		{
			return new JsonPrimitive(Base64.encodeBytes(src, Base64.DONT_BREAK_LINES));
		}
	}
	
	private static class NaNToNullAdapter implements JsonSerializer<Double>, JsonDeserializer<Double>
	{
		public Double deserialize(JsonElement json, Type typeOfT, JsonDeserializationContext context) throws JsonParseException
		{
			return json.isJsonNull() ? Double.NaN : json.getAsDouble();
		}
		public JsonElement serialize(Double src, Type typeOfSrc, JsonSerializationContext context)
		{
			return Double.isNaN(src) ? JsonNull.INSTANCE : new JsonPrimitive(src);
		}
	}
	
    private void handleArrayOfJsonRequests(PeekableInputStream inputStream,HttpServletResponse response) throws IOException
    {
    	try
    	{
    		JsonRpcRequestModel[] jsonRequests;
    		String streamString = IOUtils.toString(inputStream, "UTF-8");
    		
    		ServletRequestInfo info = getServletRequestInfo();
    		/*If first character is { then it is a single request. We add it to the array jsonRequests and continue*/
    		if (streamString.charAt(0) == '{')
    		{
    			//TODO:CHeck parse error for this
    			JsonRpcRequestModel req = GSON.fromJson(streamString, JsonRpcRequestModel.class);
    			jsonRequests = new JsonRpcRequestModel[] { req };
    			info.isBatchRequest = false;
    		}
    		else
    		{
    			jsonRequests = GSON.fromJson(streamString, JsonRpcRequestModel[].class);
    			info.isBatchRequest = true;
    		}
    		
    		
    		/* we loop through each request, get results or check error and add repsonses to an array*/ 
    		for (int i = 0; i < jsonRequests.length; i++)
    		{
				info.currentJsonRequest = jsonRequests[i];
				
				/* Check to see if JSON-RPC protocol is 2.0*/
				if (info.currentJsonRequest.jsonrpc == null || !info.currentJsonRequest.jsonrpc.equals(JSONRPC_VERSION))
				{
					sendJsonError(JSON_RPC_PROTOCOL_ERROR_MESSAGE, info.currentJsonRequest.jsonrpc);
					continue;
				}
				/*Check if ID is a number and if so it has not fractional numbers*/
				else if (info.currentJsonRequest.id instanceof Number)
				{
					Number number = (Number) info.currentJsonRequest.id;
					if (number.intValue() != number.doubleValue())
					{
						sendJsonError(JSON_RPC_ID_ERROR_MESSAGE, info.currentJsonRequest.id);
						continue;
					}
					info.currentJsonRequest.id = number.intValue();
				}
				
				/*Check if Method exists*/
				if (!methodMap.containsKey(info.currentJsonRequest.method))
				{
					sendJsonError(JSON_RPC_METHOD_ERROR_MESSAGE, info.currentJsonRequest.method);
					continue;
				}
				
				invokeMethod(info.currentJsonRequest.method, info.currentJsonRequest.params);
    		}
    		
    	}
    	catch (JsonParseException e)
    	{
    		sendError(e, JSON_RPC_PARSE_ERROR_MESSAGE);
    	}
    }
    
    private void handleJsonResponses()
    {
    	ServletRequestInfo info = getServletRequestInfo();
    	
    	if (info.currentJsonRequest == null)
    		return;
    	
    	info.response.setContentType("application/json");
    	info.response.setCharacterEncoding("UTF-8");
		String result;
    	try
    	{
    		if (info.jsonResponses.size() == 0)
    		{
    			// If there are no Response objects contained within the Response array as it is to be sent to the client,
    			// the server MUST NOT return an empty Array and should return nothing at all.
    			ServletOutputStream out = info.getOutputStream();
    			out.close();
    			out.flush();
    			return;
    		}
    		if (!info.isBatchRequest)
    		{
   				result = GSON.toJson(info.jsonResponses.get(0));
    		}
    		else
    		{
    			result = GSON.toJson(info.jsonResponses);
    		}
    		
    		PrintWriter writer = new PrintWriter(info.getOutputStream());
			writer.print(result);
			writer.close();
			writer.flush();
			
    	}
    	catch (Exception e)
    	{
			e.printStackTrace();
		}
    }
    
    private static String JSON_RPC_PROTOCOL_ERROR_MESSAGE = "JSON-RPC protocol must be 2.0";
    private static String JSON_RPC_ID_ERROR_MESSAGE = "ID cannot contain fractional parts";
    private static String JSON_RPC_METHOD_ERROR_MESSAGE = "The method does not exist or is not available.";
    private static String JSON_RPC_PARSE_ERROR_MESSAGE = "Invalid JSON was received by the server. An error occurred on the server while parsing the JSON text.";
    private void sendJsonError(String message, Object data)
    {
    	ServletRequestInfo info = getServletRequestInfo();
    	Object id = info.currentJsonRequest.id;
    	
		// If ID is empty then it is a notification and we send nothing back
		if (id == null)
			return;
    	
	    JsonRpcResponseModel result = new JsonRpcResponseModel();
	    result.id = id;
	    result.jsonrpc = "2.0";
	    result.error = new JsonRpcErrorModel();
	    result.error.message = message;
	    result.error.data = data;
	    
	    if (message.equals(JSON_RPC_PROTOCOL_ERROR_MESSAGE)
	    		|| message.equals(JSON_RPC_ID_ERROR_MESSAGE))
	    {
	    	result.error.code = "-32600";
	    }
	    else if (message.equals(JSON_RPC_METHOD_ERROR_MESSAGE))
	    {
	    	result.error.code = "-32601";
	    }
	    else if (message.equals(JSON_RPC_PARSE_ERROR_MESSAGE))
	    {
	    	result.error.code = "-32700";
	    }
	    else
	    {
	    	result.error.code = "-32000";
	    }
	    
	    info.jsonResponses.add(result);
    }
    
	@SuppressWarnings({ "rawtypes", "unchecked" })
	private Object[] getParamsFromMap(String methodName, Map params)
	{
		ExposedMethod exposedMethod = methodMap.get(methodName);
		String[] argNames = exposedMethod.paramNames;
		Class[] argTypes = exposedMethod.method.getParameterTypes();
		Object[] argValues = new Object[argTypes.length];
		
		Map extraParameters = null; // parameters that weren't mapped directly to method arguments
		
		// For each method parameter, get the corresponding url parameter value.
		if (argNames != null && params != null)
		{
			//TODO: check why params is null
			for (Object parameterName : params.keySet())
			{
				Object parameterValue = params.get(parameterName);
				int index = ListUtils.findString((String)parameterName, argNames);
				if (index >= 0)
				{
					argValues[index] = parameterValue;
				}
				else if (!parameterName.equals(METHOD))
				{
					if (extraParameters == null)
						extraParameters = new HashMap();
					extraParameters.put(parameterName, parameterValue);
				}
			}
		}
		
		// support for a function having a single Map<String,String> parameter
		// see if we can find a Map arg.  If so, set it to extraParameters
		if (argTypes != null)
		{
			for (int i = 0; i < argTypes.length; i++)
			{
				if (argTypes[i] == Map.class && argValues[i] == null)
				{
					// avoid passing a null Map to the function
					if (extraParameters == null)
						extraParameters = new HashMap<String,String>();
					argValues[i] = extraParameters;
					extraParameters = null;
					break;
				}
			}
		}
		if (extraParameters != null)
		{
			System.out.println("Received servlet request: " + methodToString(methodName, argValues));
			System.out.println("Unused parameters: "+extraParameters.entrySet());
		}
		
		return argValues;
	}
	
	/**
	 * @param methodName The name of the function to invoke.
	 * @param methodParams A Map, List, or Array of input parameters for the method.  Values will be cast to the appropriate types if necessary.
	 */
	private void invokeMethod(String methodName, Object methodParams) throws IOException
	{
		ServletRequestInfo info = getServletRequestInfo();
		if (!methodMap.containsKey(methodName) || methodMap.get(methodName) == null)
		{
			sendError(new IllegalArgumentException(String.format("Method \"%s\" not supported.", methodName)), null);
			return;
		}
		
		if (methodParams == null)
			methodParams = new Object[0];
		
		if (methodParams instanceof Map)
			methodParams = getParamsFromMap(methodName, (Map<?,?>)methodParams);
		
		if (methodParams instanceof List<?>)
			methodParams = ((List<?>)methodParams).toArray();
		
		if (info.streamParameterIndex != null)
		{
			int index = info.streamParameterIndex.intValue();
			if (index >= 0)
				((Object[])methodParams)[index] = info.inputStream;
		}
			
		Object[] params = (Object[])methodParams;
		
		// get method by name
		ExposedMethod exposedMethod = methodMap.get(methodName);
		if (exposedMethod == null)
		{
			sendError(new IllegalArgumentException("Unknown method: "+methodName), null);
			return;
		}
		
		// cast input values to appropriate types if necessary
		Class<?>[] expectedArgTypes = exposedMethod.method.getParameterTypes();
		if (expectedArgTypes.length == params.length)
		{
			for (int index = 0; index < params.length; index++)
			{
				params[index] = cast(params[index], expectedArgTypes[index]);
			}
    	}

    	// prepare to output the result of the method call
    	long startTime = System.currentTimeMillis();
    	
		// Invoke the method on the object with the arguments 
		try
		{
			Object result = exposedMethod.method.invoke(exposedMethod.instance, params);
			
			if (info.currentJsonRequest == null) // AMF3
			{
				if (exposedMethod.method.getReturnType() != void.class)
				{
					ServletOutputStream servletOutputStream = info.getOutputStream();
					serializeCompressedAmf3(result, servletOutputStream);
				}
			}
			else // json
			{
				Object id = info.currentJsonRequest.id;
				/* If ID is empty then it is a notification, we send nothing back */
				if (id != null)
				{
					JsonRpcResponseModel responseObj = new JsonRpcResponseModel();
					responseObj.jsonrpc = "2.0";
					responseObj.result = result;
					responseObj.id = id;
					info.jsonResponses.add(responseObj);
				}
			}
			
		}
		catch (InvocationTargetException e)
		{
			System.err.println(methodToString(methodName, params));
			sendError(e, null);
		}
		catch (IllegalArgumentException e)
		{
			String moreInfo = 
				"Expected: " + formatFunctionSignature(methodName, expectedArgTypes, exposedMethod.paramNames) + "\n" +
				"Received: " + formatFunctionSignature(methodName, params, null);
			
			sendError(e, moreInfo);
		}
		catch (Exception e)
		{
			System.err.println(methodToString(methodName, params));
			sendError(e, null);
		}
		
		long endTime = System.currentTimeMillis();
		// debug
		if (endTime - startTime >= debugThreshold)
			System.out.println(String.format("[%sms] %s", endTime - startTime, methodToString(methodName, params)));
    }
    
	/**
	 * Tries to convert value to the given type.
	 * @param value The value to cast to a new type.
	 * @param type The desired type.
	 * @return The value, which may have been cast as the new type.
	 */
	protected Object cast(Object value, Class<?> type) throws RemoteException
	{
		if (type.isInstance(value))
			return value;

		try
		{
			if (value == null) // null -> NaN
			{
				if (type == double.class || type == Double.class)
					value = Double.NaN;
				else if (type == float.class || type == Float.class)
					value = Float.NaN;
				return value;
			}
			
			if (value instanceof Map) // Map -> Java Bean
			{
				Object bean = type.newInstance();
				for (Field field : type.getFields())
				{
					Object fieldValue = ((Map<?,?>)value).get(field.getName());
					fieldValue = cast(fieldValue, field.getType());
					field.set(bean, fieldValue);
				}
				return bean;
			}
			
			if (type.isArray()) // ? -> T[]
			{
				if (value instanceof String) // String -> String[]
					value = CSVParser.defaultParser.parseCSVRow((String)value, true);
				
				if (value instanceof List) // List -> Object[]
					value = ((List<?>)value).toArray();
				
				if (value.getClass().isArray()) // T1[] -> T2[]
				{
					int n = Array.getLength(value);
					Class<?> itemType = type.getComponentType();
					Object output = Array.newInstance(itemType, n);
					while (n-- > 0)
						Array.set(output, n, cast(Array.get(value, n), itemType));
					return output;
				}
			}

			if (Collection.class.isAssignableFrom(type)) // ? -> <? extends Collection>
			{
				value = cast(value, Object[].class); // ? -> Object[]
				
				if (value.getClass().isArray()) // T1[] -> Vector<T2>
				{
					int n = Array.getLength(value);
					List<Object> output = new Vector<Object>(n);
					TypeVariable<?>[] itemTypes = type.getTypeParameters();
					Class<?> itemType = itemTypes.length > 0 ? itemTypes[0].getClass() : null;
					while (n-- > 0)
					{
						Object item = Array.get(value, n);
						if (itemType != null)
							item = cast(item, itemType); // T1 -> T2
						output.set(n, item);
					}
					return output;
				}
			}
			
			if (value instanceof String) // String -> ?
			{
				String string = (String)value;
				
				try // String -> primitive
				{
					if (type == char.class || type == Character.class) return string.charAt(0);
					if (type == byte.class || type == Byte.class) return Byte.parseByte(string);
					if (type == long.class || type == Long.class) return Long.parseLong(string);
					if (type == int.class || type == Integer.class) return Integer.parseInt(string);
					if (type == short.class || type == Short.class) return Short.parseShort(string);
					if (type == float.class || type == Float.class) return Float.parseFloat(string);
					if (type == double.class || type == Double.class) return Double.parseDouble(string);
					if (type == boolean.class || type == Boolean.class) return string.equalsIgnoreCase("true");
				}
				catch (NumberFormatException e)
				{
					// if number parsing fails, leave the original value untouched
				}
				
				if (type == InputStream.class) // String -> InputStream
				{
					try
					{
						return new ByteArrayInputStream(string.getBytes("UTF-8"));
					}
					catch (Exception e)
					{
						return null;
					}
				}
			}
			
			if (value instanceof Number) // Number -> primitive
			{
				Number number = (Number)value;
				if (type == byte.class || type == Byte.class) return number.byteValue();
				if (type == long.class || type == Long.class) return number.longValue();
				if (type == int.class || type == Integer.class) return number.intValue();
				if (type == short.class || type == Short.class) return number.shortValue();
				if (type == float.class || type == Float.class) return number.floatValue();
				if (type == double.class || type == Double.class) return number.doubleValue();
				if (type == char.class || type == Character.class) return Character.toChars(number.intValue())[0];
				if (type == boolean.class || type == Boolean.class) return !Double.isNaN(number.doubleValue()) && number.intValue() != 0;
			}
		}
		catch (Exception e)
		{
			throw new RemoteException(String.format("Unable to cast %s to %s", value.getClass().getName(), type.getName()), e);
		}
		
		// Return original value if not handled above.
		// Primitives and their Object equivalents will cast automatically.
		return value;
	}
	
    /**
     * This function formats a Java function signature as a String.
     * @param methodName The name of the method.
     * @param paramValuesOrTypes A list of Class objects or arbitrary Objects to get the class names from.
     * @param paramNames The names of the parameters, may be null.
     * @return A readable Java function signature.
     */
    private String formatFunctionSignature(String methodName, Object[] paramValuesOrTypes, String[] paramNames)
    {
    	// don't use paramNames if the length doesn't match the paramValuesOrTypes length.
    	if (paramNames != null && paramNames.length != paramValuesOrTypes.length)
    		paramNames = null;
    	
    	List<String> names = new Vector<String>(paramValuesOrTypes.length);
    	for (int i = 0; i < paramValuesOrTypes.length; i++)
    	{
    		Object valueOrType = paramValuesOrTypes[i];
    		String name = "null";
    		if (valueOrType instanceof Class)
    			name = ((Class<?>)valueOrType).getName();
    		else if (valueOrType != null)
    			name = valueOrType.getClass().getName();
    		
    		// decode output of Class.getName()
    		while (name.charAt(0) == '[') // array type
    		{
    			name = name.substring(1) + "[]";
    			// decode element type encoding
    			String type = "";
    			switch (name.charAt(0))
    			{
    				case 'Z': type = "boolean"; break;
    				case 'B': type = "byte"; break;
    				case 'C': type = "char"; break;
    				case 'D': type = "double"; break;
    				case 'F': type = "float"; break;
    				case 'I': type = "int"; break;
    				case 'J': type = "long"; break;
    				case 'S': type = "short"; break;
    				case 'L':
    					// remove ';'
    					name = name.replace(";", "");
    					break;
    				default: continue;
    			}
    			// remove first char encoding
    			name = type + name.substring(1);
    		}
			// hide package names
			if (name.indexOf('.') >= 0)
				name = name.substring(name.lastIndexOf('.') + 1);
    		
			if (paramNames != null)
				name += " " + paramNames[i];
			
    		names.add(name);
    	}
    	String result = names.toString();
    	return String.format("%s(%s)", methodName, result.substring(1, result.length() - 1));
    }
    
    private void sendError(Throwable exception, String moreInfo) throws IOException
	{
    	if (exception instanceof InvocationTargetException)
    		exception = exception.getCause();
    	
    	// log errors
    	exception.printStackTrace();
    	
    	String message;
    	if (exception instanceof RuntimeException)
    		message = exception.toString();
    	else
    		message = exception.getMessage();
    	
    	if (moreInfo != null)
    		message += "\n" + moreInfo;
    	
    	System.err.println("Serializing ErrorMessage: "+message);
    	
    	ServletRequestInfo info = getServletRequestInfo();
    	if (info.currentJsonRequest == null)
    	{
    		ServletOutputStream servletOutputStream = info.getOutputStream();
        	ErrorMessage errorMessage = new ErrorMessage(new MessageException(message));
        	errorMessage.faultCode = exception.getClass().getSimpleName();
        	serializeCompressedAmf3(errorMessage, servletOutputStream);
    	}
    	else
    	{
    		sendJsonError(message, null);
    	}
	}
    
    protected static SerializationContext getSerializationContext()
    {
    	SerializationContext context = SerializationContext.getSerializationContext();
    	
    	// set serialization context properties
    	context.enableSmallMessages = true;
    	context.instantiateTypes = true;
       	context.supportRemoteClass = true;
    	context.legacyCollection = false;
    	context.legacyMap = false;
    	context.legacyXMLDocument = false;
    	context.legacyXMLNamespaces = false;
    	context.legacyThrowable = false;
    	context.legacyBigNumbers = false;
    	context.restoreReferences = false;
    	context.logPropertyErrors = false;
    	context.ignorePropertyErrors = true;
    	
    	return context;
    }
    
    // Serialize a Java Object to AMF3 ByteArray
    protected void serializeCompressedAmf3(Object objToSerialize, ServletOutputStream servletOutputStream)
    {
    	try
    	{
    		SerializationContext context = getSerializationContext();

    		DeflaterOutputStream deflaterOutputStream = new DeflaterOutputStream(servletOutputStream);
    		
			Amf3Output amf3Output = new Amf3Output(context);
			amf3Output.setOutputStream(deflaterOutputStream); // compress
			amf3Output.writeObject(objToSerialize);
			amf3Output.flush();
			
			deflaterOutputStream.close(); // this is necessary to finish the compression
			
			/*
			 * Do not call amf3Output.close() because that will
			 * send a 'reset' packet and cause the response to fail.
			 * 
			 * http://viveklakhanpal.wordpress.com/2010/07/01/error-2032ioerror/
			 */
    	}
    	catch (Exception e)
    	{
    		e.printStackTrace();
    	}
    }

    //  De-serialize a ByteArray/AMF3/Flex object to a Java object  
    protected ASObject deserializeAmf3(InputStream inputStream) throws ClassNotFoundException, IOException
    {
    	ASObject deSerializedObj = null;

    	SerializationContext context = getSerializationContext();
		
    	Amf3Input amf3Input = new Amf3Input(context);
		amf3Input.setInputStream(inputStream); // uncompress
		deSerializedObj = (ASObject) amf3Input.readObject();
		//amf3Input.close();
    	
		return deSerializedObj;
    }
    
    protected String methodToString(String name, Object[] params)
    {
		String str = name + Arrays.deepToString(params);
		int max = 1024;
		if (str.length() > max)
			str = str.substring(0, max) + "...";
    	return str;
    }
}
