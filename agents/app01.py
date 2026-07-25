import streamlit as st
import pandas as pd
import json
import os
from openai import OpenAI

SERVER_URL = "http://0.0.0.0:8080/v1"


def load_test_data() -> str:
    """Loads the test results JSON data from the data directory."""
    script_dir = os.path.dirname(os.path.abspath(__file__))
    data_file_path = os.path.join(
        script_dir, "..", "data", "test-results.json"
    )
    with open(data_file_path, "r", encoding="utf-8") as f:
        return f.read()


def get_analysis_prompt(json_data: str) -> tuple[str, str]:
    """Returns the system and user analysis prompts."""
    system_prompt = (
        "You are a helpful assistant analyzing test "
        "automation metrics."
    )

    user_prompt = f"""
    You are a QA Lead analyzing automated test execution results. 
    Review the following JSON data containing test run metrics.
    
    Provide a concise summary report with:
    1. Key takeaways (overall health, biggest problem areas).
    2. Recommendations based on the failure reasons.
    
    Keep it professional, bulleted, and directly to the point.
    Do not include introductory fluff.
    
    Test Data:
    {json_data}
    """

    return system_prompt, user_prompt


def generate_llm_summary(
    json_data: str, api_key: str = "sk-local-dev-key"
) -> str:
    """Generates a summary of the test data using OpenAI."""
    if not api_key:
        return "⚠️ API Key is missing. Cannot generate summary."
    
    try:
        # Instantiate OpenAI client with the provided API key
        client = OpenAI(base_url=SERVER_URL, api_key=api_key)
        
        system_prompt, user_prompt = get_analysis_prompt(json_data)
        
        response = client.chat.completions.create(
            # You can switch to "gpt-4o" or any other supported model
            model="gpt-4o-mini",
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt}
            ],
            temperature=0.3
        )
        
        return response.choices[0].message.content
    except Exception as e:
        return f"Error generating summary: {e}"


def main():
    st.set_page_config(page_title="Test Summary Dashboard", layout="wide")

    st.title("📊 QA Test Execution Dashboard")
    st.markdown("---")

    # Load and format the data
    json_data = load_test_data()
    raw_data = json.loads(json_data)
    df = pd.DataFrame(raw_data)
    
    # Add Sr. No column (1-indexed) and move it to the front
    df.insert(0, 'Sr. No', range(1, 1 + len(df)))

    # 1. The Data Table
    st.subheader("Test Suite Metrics")
    st.dataframe(df, hide_index=True, width="stretch")

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

    # 3. The LLM Summary
    st.subheader("🤖 AI Insights & Key Takeaways")

    if "summary_text" not in st.session_state:
        st.session_state.summary_text = None

    if st.button("Generate AI Insights"):
        with st.spinner("Analyzing test data..."):
            st.session_state.summary_text = generate_llm_summary(
                json_data
            )

    if st.session_state.summary_text:
        st.info(st.session_state.summary_text)

 
if __name__ == "__main__":
    main()
