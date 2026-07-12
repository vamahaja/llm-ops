import json
import os
import sys
from openai import OpenAI

# Set LLM configuration
SERVER_URL = "http://0.0.0.0:8080/v1"
API_KEY = "sk-local-dev-key"
MODEL = "local-model"

SYSTEM_ROLE = (
    "You are a highly capable, local AI assistant deployed via Podman. "
    "Use the tools provided to read the requested file contents "
    "before answering."
)

TEMPERATURE = 0.2
MAX_TOKENS = 2000

def read_user_file(file_path: str) -> str:
    """Reads the contents of a local file and returns it as a string."""
    print(f"[Tool: read_user_file] Attempting to read: {file_path}")
    try:
        with open(file_path, "r", encoding="utf-8") as f:
            content = f.read()
            print(
                "[Tool: read_user_file] Successfully read "
                f"{len(content)} characters."
            )
            return content
    except Exception as e:
        return f"Error reading file '{file_path}': {e}"

def main():
    # 1. Determine target file from command line arguments or user input
    if len(sys.argv) < 1:
        raise Exception("Error: No target file provided.")
    target_file = sys.argv[1]

    # Check if file exists
    if not os.path.exists(target_file):
        raise Exception(f"Error: File '{target_file}' does not exist.")

    print(f"Target file selected: '{target_file}'")

    # 2. Initialize the client
    try:
        client = OpenAI(base_url=SERVER_URL, api_key=API_KEY)
    except Exception as e:
        print(f"Failed to initialize OpenAI client: {e}")
        sys.exit(1)

    # 3. Define tool specifications
    tools = [
        {
            "type": "function",
            "function": {
                "name": "read_user_file",
                "description": (
                    "Reads the contents of a local file "
                    "given by its path."
                ),
                "parameters": {
                    "type": "object",
                    "properties": {
                        "file_path": {
                            "type": "string",
                            "description": (
                                "The path to the file on the "
                                "filesystem to read."
                            )
                        }
                    },
                    "required": ["file_path"]
                }
            }
        }
    ]

    # 4. Formulate the user message requesting analysis of the file
    user_content = (
        f"Please read the file at '{target_file}' using the "
        "read_user_file tool. Once you have read it, parse and "
        "summarize its imports, structure, and main function."
    )

    messages = [
        {"role": "system", "content": SYSTEM_ROLE},
        {"role": "user", "content": user_content}
    ]

    print(
        "Sending initial request with tool definitions to "
        "local llama.cpp server ..."
    )

    try:
        # 5. First API call
        response = client.chat.completions.create(
            model=MODEL,
            messages=messages,
            tools=tools,
            tool_choice="auto",
            temperature=TEMPERATURE,
            max_tokens=MAX_TOKENS
        )

        response_message = response.choices[0].message
        
        # Check if the model wants to call any tool
        if response_message.tool_calls:
            print("\nModel requested one or more tool calls:")
            
            # OpenAI API requires appending the assistant response
            # containing tool_calls
            messages.append(response_message)
            
            for tool_call in response_message.tool_calls:
                function_name = tool_call.function.name
                function_args = json.loads(tool_call.function.arguments)
                
                if function_name == "read_user_file":
                    # Get path argument
                    path_arg = function_args.get("file_path")
                    
                    # Execute the local function
                    file_content = read_user_file(path_arg)
                    
                    # Append the tool message to messages history
                    messages.append({
                        "tool_call_id": tool_call.id,
                        "role": "tool",
                        "name": function_name,
                        "content": file_content
                    })
            
            print("\nSending tool execution results back to the server...")
            
            # 6. Second API call containing the tool execution results
            second_response = client.chat.completions.create(
                model=MODEL,
                messages=messages,
                temperature=TEMPERATURE,
                max_tokens=MAX_TOKENS
            )
            
            final_content = second_response.choices[0].message.content
            print("\n--- Final Model Response ---")
            print(final_content)
            print("----------------------------")
            
            usage = second_response.usage
            print(
                f"\n[Usage Stats]: Prompt Tokens: {usage.prompt_tokens} | "
                f"Completion Tokens: {usage.completion_tokens} | "
                f"Total: {usage.total_tokens}"
            )
        else:
            # Model responded directly without calling a tool
            print("\nModel responded directly without using tools:")
            print("\n--- Model Response ---")
            print(response_message.content)
            print("----------------------")
            
            usage = response.usage
            print(
                f"\n[Usage Stats]: Prompt Tokens: {usage.prompt_tokens} | "
                f"Completion Tokens: {usage.completion_tokens} | "
                f"Total: {usage.total_tokens}"
            )

    except Exception as e:
        print(f"\nError communicating with local server: {e}")
        print(
            "Please ensure your local llama.cpp server is "
            "running and accessible."
        )

if __name__ == "__main__":
    main()
