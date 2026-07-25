import streamlit as st
import pandas as pd
import json
import os
from openai import OpenAI

SERVER_URL = "http://0.0.0.0:8080/v1"
MODEL = "local-model"


def load_test_data() -> str:
    """Loads the test results JSON data from the data directory."""
    script_dir = os.path.dirname(os.path.abspath(__file__))
    data_file_path = os.path.join(
        script_dir, "..", "data", "test-results.json"
    )
    with open(data_file_path, "r", encoding="utf-8") as f:
        return f.read()


def get_client(api_key: str = "sk-local-dev-key") -> OpenAI:
    """Initializes and returns the OpenAI client."""
    try:
        return OpenAI(base_url=SERVER_URL, api_key=api_key)
    except Exception as e:
        st.error(f"Failed to initialize OpenAI client: {e}")
        return None


def get_tools() -> list[dict]:
    """Returns the list of tools available to the LLM agent."""
    return [
        {
            "type": "function",
            "function": {
                "name": "load_test_data",
                "description": (
                    "Loads the test results JSON data containing "
                    "test suite names, pass counts, fail counts, "
                    "and totals."
                ),
                "parameters": {
                    "type": "object",
                    "properties": {}
                }
            }
        }
    ]


def get_messages(user_query: str) -> list[dict]:
    """Constructs the messages history for the LLM request."""
    return [
        {
            "role": "system",
            "content": (
                "You are a helpful assistant analyzing test "
                "automation metrics. To answer questions about the "
                "test metrics, execution trends, or failure reasons, "
                "you MUST invoke the load_test_data tool. "
                "Do not make up metrics."
            )
        },
        {"role": "user", "content": user_query}
    ]


def execute_tool_calls(
    tool_calls, messages: list[dict], status_cont
) -> None:
    """Executes the tool calls requested by the model."""
    for tool_call in tool_calls:
        function_name = tool_call.function.name
        status_cont.write(
            f"Executing tool: `{function_name}`..."
        )

        if function_name == "load_test_data":
            tool_result = load_test_data()
            messages.append({
                "tool_call_id": tool_call.id,
                "role": "tool",
                "name": function_name,
                "content": tool_result
            })
            status_cont.write(
                "Successfully loaded metrics. "
                "Sending back to model..."
            )


def get_chat_completion(
    client: OpenAI,
    messages: list[dict],
    tools: list[dict] = None,
    tool_choice: str = None
):
    """Fetches chat completions from OpenAI client, managing exceptions."""
    try:
        kwargs = {
            "model": MODEL,
            "messages": messages,
            "temperature": 0.2,
            "max_tokens": 2000
        }
        if tools:
            kwargs["tools"] = tools
        if tool_choice:
            kwargs["tool_choice"] = tool_choice

        return client.chat.completions.create(**kwargs)
    except Exception as e:
        st.error(f"Chat completion error: {e}")
        raise e


def run_agent_workflow(
    user_query: str, api_key: str = "sk-local-dev-key"
) -> tuple[str, bool]:
    """Runs the LLM agent flow, calling load_test_data tool if requested."""
    client = get_client(api_key)
    tools = get_tools()
    messages = get_messages(user_query)

    tool_called = False

    # We use a status container to show execution steps
    with st.status("Agent is processing...", expanded=True) as status_cont:
        try:
            status_cont.write("Sending request to llama.cpp server ...")
            response = get_chat_completion(
                client=client,
                messages=messages,
                tools=tools,
                tool_choice="auto"
            )

            response_message = response.choices[0].message

            # Check if model wants to call tool
            if response_message.tool_calls:
                tool_called = True
                status_cont.write("Model requested tool execution.")
                messages.append(response_message)

                execute_tool_calls(
                    response_message.tool_calls,
                    messages,
                    status_cont
                )

                status_cont.write("Generating final response ...")
                second_response = get_chat_completion(
                    client=client,
                    messages=messages
                )

                final_content = second_response.choices[0].message.content
            else:
                final_content = (
                    response_message.content or
                    "No response content generated."
                )

            status_cont.update(
                label="Response generated!",
                state="complete",
                expanded=False
            )
            return final_content, tool_called

        except Exception as e:
            status_cont.update(
                label="Error occurred!",
                state="error",
                expanded=True
            )
            status_cont.write(f"Error during agent execution: {e}")
            return f"Error communicating with local server: {e}", False


def render_page(df: pd.DataFrame) -> None:
    """Renders the dashboard components on the page."""
    # Add Sr. No column (1-indexed) and move it to the front
    df_display = df.copy()
    df_display.insert(0, 'Sr. No', range(1, 1 + len(df_display)))

    # 1. The Data Table
    st.subheader("Test Suite Metrics")
    st.dataframe(df_display, hide_index=True, width="stretch")

    st.markdown("---")

    # 2. The Line Chart
    st.subheader("📈 Execution Trends by Suite")

    chart_data = df[
        ["Test Suite Name", "Pass", "Fails", "Totals"]
    ].set_index("Test Suite Name")

    # Green (Pass), Red (Fail), Blue (Total)
    st.line_chart(
        chart_data, color=["#28a745", "#dc3545", "#007bff"]
    )

    st.markdown("---")

    # 3. The LLM Summary (Tool Enabled)
    st.subheader("🤖 AI Insights & Key Takeaways")

    if "summary_text" not in st.session_state:
        st.session_state.summary_text = None

    if st.button("Generate AI Insights"):
        query = (
            "Summarize the test results and highlight the main "
            "takeaways and recommendations."
        )
        response_text, _ = run_agent_workflow(query)
        st.session_state.summary_text = response_text

    if st.session_state.summary_text:
        st.info(st.session_state.summary_text)


def main():
    st.set_page_config(page_title="QA Agent Dashboard", layout="wide")

    st.title("📊 QA Test Execution Dashboard (Agent Version)")
    st.markdown("---")

    # Load and format the data for static display
    json_data = load_test_data()
    raw_data = json.loads(json_data)
    df = pd.DataFrame(raw_data)

    render_page(df)


if __name__ == "__main__":
    main()
