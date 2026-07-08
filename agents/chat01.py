from openai import OpenAI
import sys

# Set LLM configuration
SERVER_URL = "http://0.0.0.0:8080/v1"
API_KEY = "sk-local-dev-key"
MODEL = "local-model"

SYSTEM_ROLE = "You are a highly capable, local AI assistant deployed via Podman. "
SYSTEM_ROLE += "Keep your answers concise and accurate."
USER_CONTENT = "What are the primary benefits of running a Large Language Model locally ?"

TEMPERATURE = 0.7
MAX_TOKENS = 1000

def main():
    # 1. Initialize the client
    try:
        client = OpenAI(base_url=SERVER_URL, api_key=API_KEY)
    except Exception as e:
        print(f"Failed to initialize OpenAI client: {e}")
        sys.exit(1)

    # 2. Define the chat messages
    messages = [
        {"role": "system", "content": SYSTEM_ROLE},
        {"role": "user", "content": USER_CONTENT}
    ]

    print("Sending request to local llama.cpp server ...")

    # 3. Send the chat request
    try:
        response = client.chat.completions.create(
            model=MODEL,
            messages=messages,
            temperature=TEMPERATURE,
            max_tokens=MAX_TOKENS
        )

        # 4. Process and display the response
        generated_text = response.choices[0].message.content

        print("\n--- Model Response ---")
        print(generated_text)
        print("----------------------")

        # Print token usage statistics
        usage = response.usage
        print(
            f"\n[Usage Stats]: Prompt Tokens: {usage.prompt_tokens} | " +
            f"Completion Tokens: {usage.completion_tokens} | " +
            f"Total: {usage.total_tokens}"
        )
    except Exception as e:
        print(f"\nError communicating with local server: {e}")
        print(
            "Ensure your Podman container is running and " +
            "the context window (-c) isn't exceeding your 6GB RAM limit."
        )


if __name__ == "__main__":
    main()