from openai import OpenAI
import sys

# Set LLM configuration
SERVER_URL = "http://0.0.0.0:8080/v1"
API_KEY = "sk-local-dev-key"
MODEL = "local-model"

SYSTEM_ROLE = "You are a highly capable, local AI assistant deployed via Podman. "
SYSTEM_ROLE += "Keep your answers concise and accurate."

TEMPERATURE = 0.7
MAX_TOKENS = 4000

def main():
    # 1. Initialize the client
    try:
        client = OpenAI(base_url=SERVER_URL, api_key=API_KEY)
    except Exception as e:
        print(f"Failed to initialize OpenAI client: {e}")
        sys.exit(1)

    # 2. Define the chat messages in memory
    messages = [
        { "role": "system", "content": SYSTEM_ROLE }
    ]

    print("Interactive chat session started. Type 'exit' or 'quit' to end.")
    print("Type 'clear' or 'reset' to clear conversation history.")
    print("----------------------------------------------------------------")

    while True:
        try:
            # 3. Get user input
            user_input = input("\nYou: ").strip()
            if not user_input:
                continue
            
            if user_input.lower() in ("exit", "quit"):
                print("Exiting chat session. Conversation history cleared. Goodbye!")
                break
                
            if user_input.lower() in ("clear", "reset"):
                messages = [
                    {"role": "system", "content": SYSTEM_ROLE}
                ]
                print("Conversation history cleared. Started a new session.")
                continue

            # Append user message
            messages.append({"role": "user", "content": user_input})
            
            print("Sending request to local llama.cpp server ...")

            # 4. Send the chat request
            response = client.chat.completions.create(
                model=MODEL,
                messages=messages,
                temperature=TEMPERATURE,
                max_tokens=MAX_TOKENS
            )

            # 5. Process and display the response
            generated_text = response.choices[0].message.content

            print("\n--- Model Response ---")
            print(generated_text)
            print("----------------------")

            # Append assistant response to messages for history
            messages.append({"role": "assistant", "content": generated_text})

            # Print token usage statistics
            usage = response.usage
            print(
                f"\n[Usage Stats]: Prompt Tokens: {usage.prompt_tokens} | " +
                f"Completion Tokens: {usage.completion_tokens} | " +
                f"Total: {usage.total_tokens}"
            )
        except KeyboardInterrupt:
            print("\nExiting chat session. Conversation history cleared. Goodbye!")
            break
        except Exception as e:
            print(f"\nError communicating with local server: {e}")
            print(
                "Ensure your Podman container is running and " +
                "the context window (-c) isn't exceeding your RAM limit."
            )

            # Remove the last user message if API failed so we don't pollute the history
            if messages and messages[-1]["role"] == "user":
                messages.pop()

if __name__ == "__main__":
    main()
