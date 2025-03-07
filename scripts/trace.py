from flask import Flask
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.instrumentation.flask import FlaskInstrumentor
from opentelemetry.exporter.jaeger.proto.grpc import JaegerExporter  # Use Jaeger gRPC exporter
from opentelemetry.sdk.trace.export import BatchSpanProcessor

# Set up OpenTelemetry tracing
trace.set_tracer_provider(TracerProvider())
tracer = trace.get_tracer(__name__)
exporter = JaegerExporter(endpoint="192.168.2.104:14250")  # Jaeger gRPC endpoint
span_processor = BatchSpanProcessor(exporter)
trace.get_tracer_provider().add_span_processor(span_processor)

app = Flask(__name__)
FlaskInstrumentor().instrument_app(app)

@app.route('/')
def hello_world():
    return 'Hello, OpenTelemetry!'

if __name__ == '__main__':
    app.run(port=5000)
