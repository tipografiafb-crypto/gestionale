--
-- PostgreSQL database dump
--

\restrict ROaGTKrdyFhWdx3ArsUjeOZYiUqCPXSqs0veNHMfkoBUzP8MbtMcLEd6eXrwT1v

-- Dumped from database version 16.9 (415ebe8)
-- Dumped by pg_dump version 16.10

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: neondb_owner
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


ALTER TABLE public.ar_internal_metadata OWNER TO neondb_owner;

--
-- Name: assets; Type: TABLE; Schema: public; Owner: neondb_owner
--

CREATE TABLE public.assets (
    id bigint NOT NULL,
    order_item_id bigint NOT NULL,
    original_url character varying NOT NULL,
    local_path character varying,
    asset_type character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


ALTER TABLE public.assets OWNER TO neondb_owner;

--
-- Name: assets_id_seq; Type: SEQUENCE; Schema: public; Owner: neondb_owner
--

CREATE SEQUENCE public.assets_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.assets_id_seq OWNER TO neondb_owner;

--
-- Name: assets_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: neondb_owner
--

ALTER SEQUENCE public.assets_id_seq OWNED BY public.assets.id;


--
-- Name: inventories; Type: TABLE; Schema: public; Owner: neondb_owner
--

CREATE TABLE public.inventories (
    id integer NOT NULL,
    product_id integer NOT NULL,
    quantity_in_stock integer DEFAULT 0,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.inventories OWNER TO neondb_owner;

--
-- Name: inventories_id_seq; Type: SEQUENCE; Schema: public; Owner: neondb_owner
--

CREATE SEQUENCE public.inventories_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.inventories_id_seq OWNER TO neondb_owner;

--
-- Name: inventories_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: neondb_owner
--

ALTER SEQUENCE public.inventories_id_seq OWNED BY public.inventories.id;


--
-- Name: order_items; Type: TABLE; Schema: public; Owner: neondb_owner
--

CREATE TABLE public.order_items (
    id bigint NOT NULL,
    order_id bigint NOT NULL,
    sku character varying NOT NULL,
    quantity integer DEFAULT 1 NOT NULL,
    raw_json text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    preprint_status character varying DEFAULT 'pending'::character varying,
    preprint_job_id character varying,
    preprint_preview_url character varying,
    print_status character varying DEFAULT 'pending'::character varying,
    print_job_id character varying,
    preprint_completed_at timestamp(6) without time zone,
    print_completed_at timestamp(6) without time zone,
    preprint_print_flow_id bigint,
    scala character varying DEFAULT '1:1'::character varying,
    materiale character varying,
    campi_custom json DEFAULT '{}'::json,
    campi_webhook json DEFAULT '{}'::json,
    print_machine_id bigint
);


ALTER TABLE public.order_items OWNER TO neondb_owner;

--
-- Name: order_items_id_seq; Type: SEQUENCE; Schema: public; Owner: neondb_owner
--

CREATE SEQUENCE public.order_items_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.order_items_id_seq OWNER TO neondb_owner;

--
-- Name: order_items_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: neondb_owner
--

ALTER SEQUENCE public.order_items_id_seq OWNED BY public.order_items.id;


--
-- Name: orders; Type: TABLE; Schema: public; Owner: neondb_owner
--

CREATE TABLE public.orders (
    id bigint NOT NULL,
    external_order_code character varying NOT NULL,
    store_id bigint NOT NULL,
    status character varying DEFAULT 'new'::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    source character varying DEFAULT 'api'::character varying,
    customer_name character varying,
    customer_note text
);


ALTER TABLE public.orders OWNER TO neondb_owner;

--
-- Name: orders_id_seq; Type: SEQUENCE; Schema: public; Owner: neondb_owner
--

CREATE SEQUENCE public.orders_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.orders_id_seq OWNER TO neondb_owner;

--
-- Name: orders_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: neondb_owner
--

ALTER SEQUENCE public.orders_id_seq OWNED BY public.orders.id;


--
-- Name: print_flow_machines; Type: TABLE; Schema: public; Owner: neondb_owner
--

CREATE TABLE public.print_flow_machines (
    id bigint NOT NULL,
    print_flow_id bigint NOT NULL,
    print_machine_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


ALTER TABLE public.print_flow_machines OWNER TO neondb_owner;

--
-- Name: print_flow_machines_id_seq; Type: SEQUENCE; Schema: public; Owner: neondb_owner
--

CREATE SEQUENCE public.print_flow_machines_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.print_flow_machines_id_seq OWNER TO neondb_owner;

--
-- Name: print_flow_machines_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: neondb_owner
--

ALTER SEQUENCE public.print_flow_machines_id_seq OWNED BY public.print_flow_machines.id;


--
-- Name: print_flows; Type: TABLE; Schema: public; Owner: neondb_owner
--

CREATE TABLE public.print_flows (
    id bigint NOT NULL,
    name character varying NOT NULL,
    notes text,
    active boolean DEFAULT true,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    preprint_webhook_id bigint,
    print_webhook_id bigint,
    label_webhook_id bigint,
    operation_id integer,
    opzioni_stampa json DEFAULT '{}'::json
);


ALTER TABLE public.print_flows OWNER TO neondb_owner;

--
-- Name: print_flows_id_seq; Type: SEQUENCE; Schema: public; Owner: neondb_owner
--

CREATE SEQUENCE public.print_flows_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.print_flows_id_seq OWNER TO neondb_owner;

--
-- Name: print_flows_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: neondb_owner
--

ALTER SEQUENCE public.print_flows_id_seq OWNED BY public.print_flows.id;


--
-- Name: print_machines; Type: TABLE; Schema: public; Owner: neondb_owner
--

CREATE TABLE public.print_machines (
    id bigint NOT NULL,
    name character varying NOT NULL,
    description text,
    active boolean DEFAULT true,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


ALTER TABLE public.print_machines OWNER TO neondb_owner;

--
-- Name: print_machines_id_seq; Type: SEQUENCE; Schema: public; Owner: neondb_owner
--

CREATE SEQUENCE public.print_machines_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.print_machines_id_seq OWNER TO neondb_owner;

--
-- Name: print_machines_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: neondb_owner
--

ALTER SEQUENCE public.print_machines_id_seq OWNED BY public.print_machines.id;


--
-- Name: product_categories; Type: TABLE; Schema: public; Owner: neondb_owner
--

CREATE TABLE public.product_categories (
    id bigint NOT NULL,
    name character varying NOT NULL,
    description text,
    active boolean DEFAULT true,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


ALTER TABLE public.product_categories OWNER TO neondb_owner;

--
-- Name: product_categories_id_seq; Type: SEQUENCE; Schema: public; Owner: neondb_owner
--

CREATE SEQUENCE public.product_categories_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.product_categories_id_seq OWNER TO neondb_owner;

--
-- Name: product_categories_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: neondb_owner
--

ALTER SEQUENCE public.product_categories_id_seq OWNED BY public.product_categories.id;


--
-- Name: product_print_flows; Type: TABLE; Schema: public; Owner: neondb_owner
--

CREATE TABLE public.product_print_flows (
    id bigint NOT NULL,
    product_id bigint NOT NULL,
    print_flow_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


ALTER TABLE public.product_print_flows OWNER TO neondb_owner;

--
-- Name: product_print_flows_id_seq; Type: SEQUENCE; Schema: public; Owner: neondb_owner
--

CREATE SEQUENCE public.product_print_flows_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.product_print_flows_id_seq OWNER TO neondb_owner;

--
-- Name: product_print_flows_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: neondb_owner
--

ALTER SEQUENCE public.product_print_flows_id_seq OWNED BY public.product_print_flows.id;


--
-- Name: products; Type: TABLE; Schema: public; Owner: neondb_owner
--

CREATE TABLE public.products (
    id bigint NOT NULL,
    sku character varying NOT NULL,
    notes text,
    active boolean DEFAULT true,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    name character varying NOT NULL,
    product_category_id bigint,
    default_print_flow_id bigint,
    min_stock_level integer DEFAULT 0
);


ALTER TABLE public.products OWNER TO neondb_owner;

--
-- Name: products_id_seq; Type: SEQUENCE; Schema: public; Owner: neondb_owner
--

CREATE SEQUENCE public.products_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.products_id_seq OWNER TO neondb_owner;

--
-- Name: products_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: neondb_owner
--

ALTER SEQUENCE public.products_id_seq OWNED BY public.products.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: neondb_owner
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


ALTER TABLE public.schema_migrations OWNER TO neondb_owner;

--
-- Name: stores; Type: TABLE; Schema: public; Owner: neondb_owner
--

CREATE TABLE public.stores (
    id bigint NOT NULL,
    code character varying NOT NULL,
    name character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    active boolean DEFAULT true
);


ALTER TABLE public.stores OWNER TO neondb_owner;

--
-- Name: stores_id_seq; Type: SEQUENCE; Schema: public; Owner: neondb_owner
--

CREATE SEQUENCE public.stores_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.stores_id_seq OWNER TO neondb_owner;

--
-- Name: stores_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: neondb_owner
--

ALTER SEQUENCE public.stores_id_seq OWNED BY public.stores.id;


--
-- Name: switch_jobs; Type: TABLE; Schema: public; Owner: neondb_owner
--

CREATE TABLE public.switch_jobs (
    id bigint NOT NULL,
    order_id bigint NOT NULL,
    switch_job_id character varying,
    status character varying DEFAULT 'pending'::character varying NOT NULL,
    result_preview_url character varying,
    log text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    job_operation_id integer
);


ALTER TABLE public.switch_jobs OWNER TO neondb_owner;

--
-- Name: switch_jobs_id_seq; Type: SEQUENCE; Schema: public; Owner: neondb_owner
--

CREATE SEQUENCE public.switch_jobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.switch_jobs_id_seq OWNER TO neondb_owner;

--
-- Name: switch_jobs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: neondb_owner
--

ALTER SEQUENCE public.switch_jobs_id_seq OWNED BY public.switch_jobs.id;


--
-- Name: switch_webhooks; Type: TABLE; Schema: public; Owner: neondb_owner
--

CREATE TABLE public.switch_webhooks (
    id bigint NOT NULL,
    name character varying NOT NULL,
    hook_path character varying NOT NULL,
    store_id bigint,
    active boolean DEFAULT true,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


ALTER TABLE public.switch_webhooks OWNER TO neondb_owner;

--
-- Name: switch_webhooks_id_seq; Type: SEQUENCE; Schema: public; Owner: neondb_owner
--

CREATE SEQUENCE public.switch_webhooks_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.switch_webhooks_id_seq OWNER TO neondb_owner;

--
-- Name: switch_webhooks_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: neondb_owner
--

ALTER SEQUENCE public.switch_webhooks_id_seq OWNED BY public.switch_webhooks.id;


--
-- Name: assets id; Type: DEFAULT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.assets ALTER COLUMN id SET DEFAULT nextval('public.assets_id_seq'::regclass);


--
-- Name: inventories id; Type: DEFAULT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.inventories ALTER COLUMN id SET DEFAULT nextval('public.inventories_id_seq'::regclass);


--
-- Name: order_items id; Type: DEFAULT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.order_items ALTER COLUMN id SET DEFAULT nextval('public.order_items_id_seq'::regclass);


--
-- Name: orders id; Type: DEFAULT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.orders ALTER COLUMN id SET DEFAULT nextval('public.orders_id_seq'::regclass);


--
-- Name: print_flow_machines id; Type: DEFAULT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.print_flow_machines ALTER COLUMN id SET DEFAULT nextval('public.print_flow_machines_id_seq'::regclass);


--
-- Name: print_flows id; Type: DEFAULT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.print_flows ALTER COLUMN id SET DEFAULT nextval('public.print_flows_id_seq'::regclass);


--
-- Name: print_machines id; Type: DEFAULT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.print_machines ALTER COLUMN id SET DEFAULT nextval('public.print_machines_id_seq'::regclass);


--
-- Name: product_categories id; Type: DEFAULT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.product_categories ALTER COLUMN id SET DEFAULT nextval('public.product_categories_id_seq'::regclass);


--
-- Name: product_print_flows id; Type: DEFAULT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.product_print_flows ALTER COLUMN id SET DEFAULT nextval('public.product_print_flows_id_seq'::regclass);


--
-- Name: products id; Type: DEFAULT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.products ALTER COLUMN id SET DEFAULT nextval('public.products_id_seq'::regclass);


--
-- Name: stores id; Type: DEFAULT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.stores ALTER COLUMN id SET DEFAULT nextval('public.stores_id_seq'::regclass);


--
-- Name: switch_jobs id; Type: DEFAULT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.switch_jobs ALTER COLUMN id SET DEFAULT nextval('public.switch_jobs_id_seq'::regclass);


--
-- Name: switch_webhooks id; Type: DEFAULT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.switch_webhooks ALTER COLUMN id SET DEFAULT nextval('public.switch_webhooks_id_seq'::regclass);


--
-- Data for Name: ar_internal_metadata; Type: TABLE DATA; Schema: public; Owner: neondb_owner
--

COPY public.ar_internal_metadata (key, value, created_at, updated_at) FROM stdin;
environment	development	2025-11-20 17:28:58.888368	2025-11-20 17:28:58.888373
\.


--
-- Data for Name: assets; Type: TABLE DATA; Schema: public; Owner: neondb_owner
--

COPY public.assets (id, order_item_id, original_url, local_path, asset_type, created_at, updated_at) FROM stdin;
11	5	https://es.thepickshouse.com/wp-content/uploads/2025/01/standard-black.png	storage/TPH_ES/ES7024/TPH101-100/product_image_standard-black.png	product_image	2025-11-21 19:10:24.475591	2025-11-21 19:11:23.017252
12	5	https://es.thepickshouse.com/wp-content/uploads/lumise_data/orders/2025/11/zQ2Kg3rkS0-stage1.png	storage/TPH_ES/ES7024/TPH101-100/print_file_1_zQ2Kg3rkS0-stage1.png	print_file_1	2025-11-21 19:10:24.49949	2025-11-21 19:11:24.296374
13	5	https://es.thepickshouse.com/wp-content/uploads/lumise_data/orders/2025/11/auSnQrgbyN.png	storage/TPH_ES/ES7024/TPH101-100/screenshot_1_auSnQrgbyN.png	screenshot_1	2025-11-21 19:10:24.522089	2025-11-21 19:11:25.348344
14	6	https://es.thepickshouse.com/wp-content/uploads/2025/09/TIN-SMALL.webp	storage/TPH_ES/ES7024/TPH500/product_image_TIN-SMALL.webp	product_image	2025-11-21 19:10:24.589591	2025-11-21 19:11:25.9
15	6	https://es.thepickshouse.com/wp-content/uploads/lumise_data/orders/2025/11/0EWYCDhgAK-stage1.png	storage/TPH_ES/ES7024/TPH500/print_file_1_0EWYCDhgAK-stage1.png	print_file_1	2025-11-21 19:10:24.616186	2025-11-21 19:11:27.192199
16	6	https://es.thepickshouse.com/wp-content/uploads/lumise_data/orders/2025/11/UFe7pPQb4k.png	storage/TPH_ES/ES7024/TPH500/screenshot_1_UFe7pPQb4k.png	screenshot_1	2025-11-21 19:10:24.640503	2025-11-21 19:11:27.935134
17	7	https://es.thepickshouse.com/wp-content/uploads/2020/06/maglietta.jpg	storage/TPH_ES/ES7024/SKU-4-3/product_image_maglietta.jpg	product_image	2025-11-21 19:10:24.70997	2025-11-21 19:11:28.792656
18	7	https://es.thepickshouse.com/wp-content/uploads/lumise_data/orders/2025/11/PuCXEDLNRc-stage1.png	storage/TPH_ES/ES7024/SKU-4-3/print_file_1_PuCXEDLNRc-stage1.png	print_file_1	2025-11-21 19:10:24.733282	2025-11-21 19:11:30.15408
19	7	https://es.thepickshouse.com/wp-content/uploads/lumise_data/orders/2025/11/JVG8hIkOFx-stage2.png	storage/TPH_ES/ES7024/SKU-4-3/print_file_2_JVG8hIkOFx-stage2.png	print_file_2	2025-11-21 19:10:24.757402	2025-11-21 19:11:30.963245
20	7	https://es.thepickshouse.com/wp-content/uploads/lumise_data/orders/2025/11/1Qn5tfBmgb.png	storage/TPH_ES/ES7024/SKU-4-3/screenshot_1_1Qn5tfBmgb.png	screenshot_1	2025-11-21 19:10:24.782152	2025-11-21 19:11:31.873174
23	13	https://tph-order.s3.eu-west-3.amazonaws.com/wc-ai-customizer/2025/11/print-33619-1763755482469-stage1.png	storage/TPH_EU/EU12347/TPH002-88/print_file_1_print-33619-1763755482469-stage1.png	print_file_1	2025-11-21 22:14:16.251575	2025-11-21 22:14:17.675944
24	13	https://tph-order.s3.eu-west-3.amazonaws.com/wc-ai-customizer/2025/11/screenshot-33619-1763755482469-stage1.png	storage/TPH_EU/EU12347/TPH002-88/screenshot_1_screenshot-33619-1763755482469-stage1.png	screenshot_1	2025-11-21 22:14:16.280228	2025-11-21 22:14:18.239928
25	15	https://tph-order.s3.eu-west-3.amazonaws.com/wc-ai-customizer/2025/11/print-34417-1763752247986-stage1.png	storage/TPH_EU/EU12345/TPH502/print_file_1_print-34417-1763752247986-stage1.png	print_file_1	2025-11-21 22:21:18.379622	2025-11-21 22:21:20.047337
26	15	https://tph-order.s3.eu-west-3.amazonaws.com/wc-ai-customizer/2025/11/screenshot-34417-1763752247986-stage1.png	storage/TPH_EU/EU12345/TPH502/screenshot_1_screenshot-34417-1763752247986-stage1.png	screenshot_1	2025-11-21 22:21:18.404598	2025-11-21 22:21:20.571306
27	16	https://tph-order.s3.eu-west-3.amazonaws.com/wc-ai-customizer/2025/11/print-34204-1763752505570-stage1.png	storage/TPH_EU/EU12345/TPH500/print_file_1_print-34204-1763752505570-stage1.png	print_file_1	2025-11-21 22:21:18.467506	2025-11-21 22:21:21.731199
28	16	https://tph-order.s3.eu-west-3.amazonaws.com/wc-ai-customizer/2025/11/screenshot-34204-1763752505570-stage1.png	storage/TPH_EU/EU12345/TPH500/screenshot_1_screenshot-34204-1763752505570-stage1.png	screenshot_1	2025-11-21 22:21:18.488566	2025-11-21 22:21:22.242399
29	17	https://thepickshouse.com/wp-content/uploads/lumise_data/orders/2025/11/AMbyo632uq-stage1.png	storage/TPH_EU/EU12345/TPH205-88/print_file_1_AMbyo632uq-stage1.png	print_file_1	2025-11-21 22:21:18.554009	2025-11-21 22:21:22.429568
30	17	https://thepickshouse.com/wp-content/uploads/lumise_data/orders/2025/11/Mv3rysHu6n.png	storage/TPH_EU/EU12345/TPH205-88/screenshot_1_Mv3rysHu6n.png	screenshot_1	2025-11-21 22:21:18.580803	2025-11-21 22:21:22.555715
44	25	IMG_2495.png	\N	print	2025-11-22 15:13:30.3898	2025-11-22 16:12:29.987632
\.


--
-- Data for Name: inventories; Type: TABLE DATA; Schema: public; Owner: neondb_owner
--

COPY public.inventories (id, product_id, quantity_in_stock, created_at, updated_at) FROM stdin;
2	8	5000	2025-11-24 10:24:47.36055	2025-11-24 10:30:53.032657
3	9	0	2025-11-24 13:30:20.529255	2025-11-24 13:30:20.529255
4	10	0	2025-11-24 15:16:37.994535	2025-11-25 20:57:54.302893
1	7	1250	2025-11-24 10:13:03.233684	2025-11-25 21:09:16.494594
\.


--
-- Data for Name: order_items; Type: TABLE DATA; Schema: public; Owner: neondb_owner
--

COPY public.order_items (id, order_id, sku, quantity, raw_json, created_at, updated_at, preprint_status, preprint_job_id, preprint_preview_url, print_status, print_job_id, preprint_completed_at, print_completed_at, preprint_print_flow_id, scala, materiale, campi_custom, campi_webhook, print_machine_id) FROM stdin;
15	8	TPH502	1	{"sku":"TPH502","quantity":1,"product_name":"Unknown Product","product_image_url":"https://thepickshouse.com/wp-content/uploads/2025/09/Tin-NEW-20254.webp","print_files":["https://tph-order.s3.eu-west-3.amazonaws.com/wc-ai-customizer/2025/11/print-34417-1763752247986-stage1.png"],"screenshots":["https://tph-order.s3.eu-west-3.amazonaws.com/wc-ai-customizer/2025/11/screenshot-34417-1763752247986-stage1.png"],"raw_data":{}}	2025-11-21 22:21:18.335217	2025-11-22 19:41:51.076349	pending	\N	\N	pending	\N	\N	\N	\N	1:1	\N	{}	{}	\N
5	4	TPH101-100	5	{"sku":"TPH101-100","quantity":5,"product_name":"Púas negras de Delrin","product_image_url":"https://es.thepickshouse.com/wp-content/uploads/2025/01/standard-black.png","print_files":["https://es.thepickshouse.com/wp-content/uploads/lumise_data/orders/2025/11/zQ2Kg3rkS0-stage1.png"],"screenshots":["https://es.thepickshouse.com/wp-content/uploads/lumise_data/orders/2025/11/auSnQrgbyN.png"],"raw_data":{"id":"variable:8848","cart_id":"MI8PGBZ7","qty":5,"product_id":"variable:8848","product_cms":8838,"product_name":"Púas negras de Delrin","price":{"total":16,"fixed":0,"resource":0,"template":0,"base":3.2,"printing_price":0},"options":{"quantity":"5"},"variation":null,"attributes":{"quantity":{"id":"quantity","name":"Cantidad","value":"5","type":"quantity"}},"ext_attributes":{"pa_grosor":"1-00-heavy","pa_caras-de-impresion":"1-cara"},"printing":11,"resource":[],"template":false,"file":"2025/11/MI8PGBZ7_OkhddRcoDk"}}	2025-11-21 19:10:24.423249	2025-11-21 19:10:24.451979	pending	\N	\N	pending	\N	\N	\N	\N	1:1	\N	{}	{}	\N
6	4	TPH500	1	{"sku":"TPH500","quantity":1,"product_name":"Tin Picks - 60x34x10","product_image_url":"https://es.thepickshouse.com/wp-content/uploads/2025/09/TIN-SMALL.webp","print_files":["https://es.thepickshouse.com/wp-content/uploads/lumise_data/orders/2025/11/0EWYCDhgAK-stage1.png"],"screenshots":["https://es.thepickshouse.com/wp-content/uploads/lumise_data/orders/2025/11/UFe7pPQb4k.png"],"raw_data":{"id":"variable:11207","cart_id":"MI8PH312","qty":1,"product_id":"variable:11207","product_cms":11205,"product_name":"Tin Picks - 60x34x10","price":{"total":5,"fixed":0,"resource":0,"template":0,"base":5,"printing_price":0},"options":{"quantity":"1"},"variation":null,"attributes":{"quantity":{"id":"quantity","name":"Cantidad","value":"1","type":"quantity"}},"ext_attributes":{"pa_tin-size":"60x34x10"},"printing":null,"resource":[],"template":false,"file":"2025/11/MI8PH312_M80AZasi7w"}}	2025-11-21 19:10:24.544769	2025-11-21 19:10:24.566876	pending	\N	\N	pending	\N	\N	\N	\N	1:1	\N	{}	{}	\N
7	4	SKU-4-3	1	{"sku":"","quantity":1,"product_name":"T-shirt","product_image_url":"https://es.thepickshouse.com/wp-content/uploads/2020/06/maglietta.jpg","print_files":["https://es.thepickshouse.com/wp-content/uploads/lumise_data/orders/2025/11/PuCXEDLNRc-stage1.png","https://es.thepickshouse.com/wp-content/uploads/lumise_data/orders/2025/11/JVG8hIkOFx-stage2.png"],"screenshots":["https://es.thepickshouse.com/wp-content/uploads/lumise_data/orders/2025/11/1Qn5tfBmgb.png"],"raw_data":{"id":"43","cart_id":"MI8R3O77","qty":1,"product_id":"43","product_cms":"2375","product_name":"T-shirt","price":{"total":17.9,"fixed":0,"resource":0,"template":0,"base":17.9,"printing_price":0},"options":{"464T":"#323232","89BU":"{\\"s\\":\\"0\\",\\"m\\":\\"0\\",\\"l\\":\\"0\\",\\"xl\\":\\"1\\",\\"xxl\\":\\"0\\"}"},"variation":null,"attributes":{"464T":{"id":"464T","name":"Color","type":"product_color","required":true,"use_variation":false,"values":{"options":[{"title":"Blanco","value":"#ffffff","price":"","default":true},{"title":"Negro","value":"#323232","price":"","default":false}]},"value":"#323232"},"89BU":{"id":"89BU","name":"Cantidad y tamaño","type":"quantity","required":false,"use_variation":false,"values":{"type":"multiple","min_qty":"","max_qty":"","multiple_options":[{"value":"s","title":"S","price":"","min_qty":"","max_qty":""},{"value":"m","title":"M","price":"","min_qty":"","max_qty":""},{"value":"l","title":"L","price":"","min_qty":"","max_qty":""},{"value":"xl","title":"XL","price":"","min_qty":"","max_qty":""},{"value":"xxl","title":"XXL","price":"","min_qty":"","max_qty":""}],"package_options":[{"value":"10","title":"Package 1","price":""},{"value":"50","title":"Package 2","price":"-1"}]},"value":"{\\"s\\":\\"0\\",\\"m\\":\\"0\\",\\"l\\":\\"0\\",\\"xl\\":\\"1\\",\\"xxl\\":\\"0\\"}"}},"printing":5,"resource":[],"template":false,"file":"2025/11/MI8R3O77_PjDRGEnlOT"}}	2025-11-21 19:10:24.663746	2025-11-21 19:10:24.686654	pending	\N	\N	pending	\N	\N	\N	\N	1:1	\N	{}	{}	\N
13	7	TPH002-88	200	{"sku":"TPH002-88","quantity":200,"product_name":"Unknown Product","product_image_url":"https://thepickshouse.com/wp-content/uploads/2024/10/standard-black.webp","print_files":["https://tph-order.s3.eu-west-3.amazonaws.com/wc-ai-customizer/2025/11/print-33619-1763755482469-stage1.png"],"screenshots":["https://tph-order.s3.eu-west-3.amazonaws.com/wc-ai-customizer/2025/11/screenshot-33619-1763755482469-stage1.png"],"raw_data":{}}	2025-11-21 22:14:16.195363	2025-11-21 22:14:16.224931	pending	\N	\N	pending	\N	\N	\N	\N	1:1	\N	{}	{}	\N
14	7	TPH952	200	{"sku":"TPH952","quantity":200,"product_name":"Unknown Product","product_image_url":"https://thepickshouse.com/wp-content/uploads/2023/12/100-plettri.jpg","print_files":[],"screenshots":[],"raw_data":{}}	2025-11-21 22:14:16.301445	2025-11-21 22:14:16.322475	pending	\N	\N	pending	\N	\N	\N	\N	1:1	\N	{}	{}	\N
16	8	TPH500	1	{"sku":"TPH500","quantity":1,"product_name":"Unknown Product","product_image_url":"https://thepickshouse.com/wp-content/uploads/2025/09/Tin-NEW-20254.webp","print_files":["https://tph-order.s3.eu-west-3.amazonaws.com/wc-ai-customizer/2025/11/print-34204-1763752505570-stage1.png"],"screenshots":["https://tph-order.s3.eu-west-3.amazonaws.com/wc-ai-customizer/2025/11/screenshot-34204-1763752505570-stage1.png"],"raw_data":{}}	2025-11-21 22:21:18.425377	2025-11-24 09:45:20.128765	pending	\N	\N	pending	\N	2025-11-24 09:41:21.014038	2025-11-22 23:12:47.766564	1	1:1	\N	{}	{"percentuale":"0"}	1
25	13	TPH9L1	5	{"sku":"TPH9L1","quantity":"5","product_name":"Plettri"}	2025-11-22 15:13:30.321969	2025-11-22 15:13:43.137866	pending	\N	\N	pending	\N	\N	\N	\N	1:1	\N	{}	{}	\N
17	8	TPH205-88	9	{"sku":"TPH205-88","quantity":9,"product_name":"Dunlop Flow - 0.88 - Heavy","product_image_url":"https://thepickshouse.com/wp-content/uploads/2024/05/flow088.webp","print_files":["https://thepickshouse.com/wp-content/uploads/lumise_data/orders/2025/11/AMbyo632uq-stage1.png"],"screenshots":["https://thepickshouse.com/wp-content/uploads/lumise_data/orders/2025/11/Mv3rysHu6n.png"],"raw_data":{"id":"variable:23142","cart_id":"MI98B4S9","qty":9,"product_id":"variable:23142","product_cms":23141,"product_name":"Dunlop Flow - 0.88 - Heavy","price":{"total":19.998,"fixed":0,"resource":0,"template":0,"base":1,"printing_price":1.222},"options":{"quantity":"9"},"variation":null,"attributes":{"quantity":{"id":"quantity","name":"Quantity","value":"9","type":"quantity"}},"ext_attributes":{"pa_thickness":"0-88-heavy"},"printing":13,"resource":[],"template":false,"file":"2025/11/MI98B4S9_imVgd2RMlY"}}	2025-11-21 22:21:18.510728	2025-11-25 20:59:06.371581	failed	\N	\N	pending	\N	\N	\N	1	1:1	\N	{}	{"percentuale":"0"}	\N
\.


--
-- Data for Name: orders; Type: TABLE DATA; Schema: public; Owner: neondb_owner
--

COPY public.orders (id, external_order_code, store_id, status, created_at, updated_at, source, customer_name, customer_note) FROM stdin;
4	ES7024	4	error	2025-11-21 19:10:24.395565	2025-11-21 21:46:34.481811	ftp	\N	PREGUNTAR POR LILIBETH PEREIRA
7	EU12347	5	new	2025-11-21 22:14:16.163634	2025-11-21 22:14:16.163634	ftp	\N	
8	EU12345	5	new	2025-11-21 22:21:18.307589	2025-11-21 22:21:18.307589	ftp	\N	
13	Paolo	4	new	2025-11-22 15:13:30.253635	2025-11-22 15:13:30.253635	api	\N	\N
\.


--
-- Data for Name: print_flow_machines; Type: TABLE DATA; Schema: public; Owner: neondb_owner
--

COPY public.print_flow_machines (id, print_flow_id, print_machine_id, created_at, updated_at) FROM stdin;
1	1	1	2025-11-23 15:09:29.871801	2025-11-23 15:09:29.871801
2	2	1	2025-11-24 09:43:47.333484	2025-11-24 09:43:47.333484
\.


--
-- Data for Name: print_flows; Type: TABLE DATA; Schema: public; Owner: neondb_owner
--

COPY public.print_flows (id, name, notes, active, created_at, updated_at, preprint_webhook_id, print_webhook_id, label_webhook_id, operation_id, opzioni_stampa) FROM stdin;
1	Plettri		t	2025-11-21 22:28:05.186728	2025-11-21 22:34:21.696341	1	1	\N	\N	{}
2	Plettri bianchi		t	2025-11-22 17:00:57.216778	2025-11-22 17:00:57.216778	1	1	1	\N	{}
\.


--
-- Data for Name: print_machines; Type: TABLE DATA; Schema: public; Owner: neondb_owner
--

COPY public.print_machines (id, name, description, active, created_at, updated_at) FROM stdin;
1	signracer		t	2025-11-23 15:04:27.865996	2025-11-23 15:04:27.865996
\.


--
-- Data for Name: product_categories; Type: TABLE DATA; Schema: public; Owner: neondb_owner
--

COPY public.product_categories (id, name, description, active, created_at, updated_at) FROM stdin;
1	Plettri		t	2025-11-21 22:48:58.981537	2025-11-21 22:48:58.981537
\.


--
-- Data for Name: product_print_flows; Type: TABLE DATA; Schema: public; Owner: neondb_owner
--

COPY public.product_print_flows (id, product_id, print_flow_id, created_at, updated_at) FROM stdin;
1	7	1	2025-11-22 17:09:37.656868	2025-11-22 17:09:37.656868
2	7	2	2025-11-22 17:09:37.683479	2025-11-22 17:09:37.683479
3	8	1	2025-11-24 10:24:47.495185	2025-11-24 10:24:47.495185
4	8	2	2025-11-24 10:24:47.521954	2025-11-24 10:24:47.521954
5	9	1	2025-11-24 13:30:20.658879	2025-11-24 13:30:20.658879
6	9	2	2025-11-24 13:30:20.723483	2025-11-24 13:30:20.723483
9	10	1	2025-11-25 20:58:16.898105	2025-11-25 20:58:16.898105
10	10	2	2025-11-25 20:58:16.963898	2025-11-25 20:58:16.963898
\.


--
-- Data for Name: products; Type: TABLE DATA; Schema: public; Owner: neondb_owner
--

COPY public.products (id, sku, notes, active, created_at, updated_at, name, product_category_id, default_print_flow_id, min_stock_level) FROM stdin;
8	TPH001-96		t	2025-11-24 10:24:47.315606	2025-11-24 10:24:47.315606	cellulide bianco 96	\N	1	5000
9	TPH001-150		t	2025-11-24 13:30:20.436191	2025-11-24 13:30:39.725317	cellulide bianco150	\N	1	5000
7	TPH001-71		t	2025-11-22 17:09:37.496119	2025-11-24 13:30:58.861939	celluloide bianchi 71	\N	1	5000
10	TPH205-88		t	2025-11-24 15:16:37.892173	2025-11-25 20:58:16.573821	cellulide bianco 88	\N	1	5000
\.


--
-- Data for Name: schema_migrations; Type: TABLE DATA; Schema: public; Owner: neondb_owner
--

COPY public.schema_migrations (version) FROM stdin;
1
2
3
4
5
20251121182018
20251121185221
20251121191420
20251121192144
20251121193043
20251121204148
1763763615
1763763616
1763763939
1763764998
1763765000
20251122084500
20251122085000
20251122
20251122085002
20251122085003
20251122085004
20251122085005
1763907186
20251123120000
20251123120001
20251123120002
\.


--
-- Data for Name: stores; Type: TABLE DATA; Schema: public; Owner: neondb_owner
--

COPY public.stores (id, code, name, created_at, updated_at, active) FROM stdin;
1	magenta_001	Negozio Demo	2025-11-20 18:32:13.552881	2025-11-20 18:32:13.552881	t
4	TPH_ES	TPH ES	2025-11-21 19:10:24.326032	2025-11-21 19:10:24.326032	t
5	TPH_EU	TPH EU	2025-11-21 21:55:34.900568	2025-11-21 21:55:34.900568	t
\.


--
-- Data for Name: switch_jobs; Type: TABLE DATA; Schema: public; Owner: neondb_owner
--

COPY public.switch_jobs (id, order_id, switch_job_id, status, result_preview_url, log, created_at, updated_at, job_operation_id) FROM stdin;
3	4	\N	failed	\N	[2025-11-21 21:46:34] Exception: failed to connect: Connection refused - connect(2) for "localhost" port 9000\n[2025-11-21 21:46:41] Exception: failed to connect: Connection refused - connect(2) for "localhost" port 9000	2025-11-21 21:46:34.249579	2025-11-21 21:46:41.039288	\N
\.


--
-- Data for Name: switch_webhooks; Type: TABLE DATA; Schema: public; Owner: neondb_owner
--

COPY public.switch_webhooks (id, name, hook_path, store_id, active, created_at, updated_at) FROM stdin;
1	Test	/test	\N	t	2025-11-21 20:38:03.67632	2025-11-21 20:38:03.67632
\.


--
-- Name: assets_id_seq; Type: SEQUENCE SET; Schema: public; Owner: neondb_owner
--

SELECT pg_catalog.setval('public.assets_id_seq', 50, true);


--
-- Name: inventories_id_seq; Type: SEQUENCE SET; Schema: public; Owner: neondb_owner
--

SELECT pg_catalog.setval('public.inventories_id_seq', 4, true);


--
-- Name: order_items_id_seq; Type: SEQUENCE SET; Schema: public; Owner: neondb_owner
--

SELECT pg_catalog.setval('public.order_items_id_seq', 35, true);


--
-- Name: orders_id_seq; Type: SEQUENCE SET; Schema: public; Owner: neondb_owner
--

SELECT pg_catalog.setval('public.orders_id_seq', 21, true);


--
-- Name: print_flow_machines_id_seq; Type: SEQUENCE SET; Schema: public; Owner: neondb_owner
--

SELECT pg_catalog.setval('public.print_flow_machines_id_seq', 2, true);


--
-- Name: print_flows_id_seq; Type: SEQUENCE SET; Schema: public; Owner: neondb_owner
--

SELECT pg_catalog.setval('public.print_flows_id_seq', 2, true);


--
-- Name: print_machines_id_seq; Type: SEQUENCE SET; Schema: public; Owner: neondb_owner
--

SELECT pg_catalog.setval('public.print_machines_id_seq', 1, true);


--
-- Name: product_categories_id_seq; Type: SEQUENCE SET; Schema: public; Owner: neondb_owner
--

SELECT pg_catalog.setval('public.product_categories_id_seq', 1, true);


--
-- Name: product_print_flows_id_seq; Type: SEQUENCE SET; Schema: public; Owner: neondb_owner
--

SELECT pg_catalog.setval('public.product_print_flows_id_seq', 10, true);


--
-- Name: products_id_seq; Type: SEQUENCE SET; Schema: public; Owner: neondb_owner
--

SELECT pg_catalog.setval('public.products_id_seq', 10, true);


--
-- Name: stores_id_seq; Type: SEQUENCE SET; Schema: public; Owner: neondb_owner
--

SELECT pg_catalog.setval('public.stores_id_seq', 5, true);


--
-- Name: switch_jobs_id_seq; Type: SEQUENCE SET; Schema: public; Owner: neondb_owner
--

SELECT pg_catalog.setval('public.switch_jobs_id_seq', 3, true);


--
-- Name: switch_webhooks_id_seq; Type: SEQUENCE SET; Schema: public; Owner: neondb_owner
--

SELECT pg_catalog.setval('public.switch_webhooks_id_seq', 1, true);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: assets assets_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.assets
    ADD CONSTRAINT assets_pkey PRIMARY KEY (id);


--
-- Name: inventories inventories_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.inventories
    ADD CONSTRAINT inventories_pkey PRIMARY KEY (id);


--
-- Name: inventories inventories_product_id_key; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.inventories
    ADD CONSTRAINT inventories_product_id_key UNIQUE (product_id);


--
-- Name: order_items order_items_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT order_items_pkey PRIMARY KEY (id);


--
-- Name: orders orders_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_pkey PRIMARY KEY (id);


--
-- Name: print_flow_machines print_flow_machines_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.print_flow_machines
    ADD CONSTRAINT print_flow_machines_pkey PRIMARY KEY (id);


--
-- Name: print_flows print_flows_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.print_flows
    ADD CONSTRAINT print_flows_pkey PRIMARY KEY (id);


--
-- Name: print_machines print_machines_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.print_machines
    ADD CONSTRAINT print_machines_pkey PRIMARY KEY (id);


--
-- Name: product_categories product_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.product_categories
    ADD CONSTRAINT product_categories_pkey PRIMARY KEY (id);


--
-- Name: product_print_flows product_print_flows_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.product_print_flows
    ADD CONSTRAINT product_print_flows_pkey PRIMARY KEY (id);


--
-- Name: products products_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: stores stores_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.stores
    ADD CONSTRAINT stores_pkey PRIMARY KEY (id);


--
-- Name: switch_jobs switch_jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.switch_jobs
    ADD CONSTRAINT switch_jobs_pkey PRIMARY KEY (id);


--
-- Name: switch_webhooks switch_webhooks_pkey; Type: CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.switch_webhooks
    ADD CONSTRAINT switch_webhooks_pkey PRIMARY KEY (id);


--
-- Name: index_assets_on_order_item_id; Type: INDEX; Schema: public; Owner: neondb_owner
--

CREATE INDEX index_assets_on_order_item_id ON public.assets USING btree (order_item_id);


--
-- Name: index_order_items_on_order_id; Type: INDEX; Schema: public; Owner: neondb_owner
--

CREATE INDEX index_order_items_on_order_id ON public.order_items USING btree (order_id);


--
-- Name: index_order_items_on_preprint_print_flow_id; Type: INDEX; Schema: public; Owner: neondb_owner
--

CREATE INDEX index_order_items_on_preprint_print_flow_id ON public.order_items USING btree (preprint_print_flow_id);


--
-- Name: index_order_items_on_preprint_status; Type: INDEX; Schema: public; Owner: neondb_owner
--

CREATE INDEX index_order_items_on_preprint_status ON public.order_items USING btree (preprint_status);


--
-- Name: index_order_items_on_print_status; Type: INDEX; Schema: public; Owner: neondb_owner
--

CREATE INDEX index_order_items_on_print_status ON public.order_items USING btree (print_status);


--
-- Name: index_orders_on_store_id; Type: INDEX; Schema: public; Owner: neondb_owner
--

CREATE INDEX index_orders_on_store_id ON public.orders USING btree (store_id);


--
-- Name: index_orders_on_store_id_and_external_order_code; Type: INDEX; Schema: public; Owner: neondb_owner
--

CREATE UNIQUE INDEX index_orders_on_store_id_and_external_order_code ON public.orders USING btree (store_id, external_order_code);


--
-- Name: index_print_flow_machines_on_print_flow_id; Type: INDEX; Schema: public; Owner: neondb_owner
--

CREATE INDEX index_print_flow_machines_on_print_flow_id ON public.print_flow_machines USING btree (print_flow_id);


--
-- Name: index_print_flow_machines_on_print_flow_id_and_print_machine_id; Type: INDEX; Schema: public; Owner: neondb_owner
--

CREATE UNIQUE INDEX index_print_flow_machines_on_print_flow_id_and_print_machine_id ON public.print_flow_machines USING btree (print_flow_id, print_machine_id);


--
-- Name: index_print_flow_machines_on_print_machine_id; Type: INDEX; Schema: public; Owner: neondb_owner
--

CREATE INDEX index_print_flow_machines_on_print_machine_id ON public.print_flow_machines USING btree (print_machine_id);


--
-- Name: index_print_flows_on_label_webhook_id; Type: INDEX; Schema: public; Owner: neondb_owner
--

CREATE INDEX index_print_flows_on_label_webhook_id ON public.print_flows USING btree (label_webhook_id);


--
-- Name: index_print_flows_on_name; Type: INDEX; Schema: public; Owner: neondb_owner
--

CREATE UNIQUE INDEX index_print_flows_on_name ON public.print_flows USING btree (name);


--
-- Name: index_print_flows_on_preprint_webhook_id; Type: INDEX; Schema: public; Owner: neondb_owner
--

CREATE INDEX index_print_flows_on_preprint_webhook_id ON public.print_flows USING btree (preprint_webhook_id);


--
-- Name: index_print_flows_on_print_webhook_id; Type: INDEX; Schema: public; Owner: neondb_owner
--

CREATE INDEX index_print_flows_on_print_webhook_id ON public.print_flows USING btree (print_webhook_id);


--
-- Name: index_print_machines_on_name; Type: INDEX; Schema: public; Owner: neondb_owner
--

CREATE UNIQUE INDEX index_print_machines_on_name ON public.print_machines USING btree (name);


--
-- Name: index_product_categories_on_name; Type: INDEX; Schema: public; Owner: neondb_owner
--

CREATE UNIQUE INDEX index_product_categories_on_name ON public.product_categories USING btree (name);


--
-- Name: index_product_print_flows_on_print_flow_id; Type: INDEX; Schema: public; Owner: neondb_owner
--

CREATE INDEX index_product_print_flows_on_print_flow_id ON public.product_print_flows USING btree (print_flow_id);


--
-- Name: index_product_print_flows_on_product_id; Type: INDEX; Schema: public; Owner: neondb_owner
--

CREATE INDEX index_product_print_flows_on_product_id ON public.product_print_flows USING btree (product_id);


--
-- Name: index_product_print_flows_on_product_id_and_print_flow_id; Type: INDEX; Schema: public; Owner: neondb_owner
--

CREATE UNIQUE INDEX index_product_print_flows_on_product_id_and_print_flow_id ON public.product_print_flows USING btree (product_id, print_flow_id);


--
-- Name: index_products_on_default_print_flow_id; Type: INDEX; Schema: public; Owner: neondb_owner
--

CREATE INDEX index_products_on_default_print_flow_id ON public.products USING btree (default_print_flow_id);


--
-- Name: index_products_on_product_category_id; Type: INDEX; Schema: public; Owner: neondb_owner
--

CREATE INDEX index_products_on_product_category_id ON public.products USING btree (product_category_id);


--
-- Name: index_products_on_sku; Type: INDEX; Schema: public; Owner: neondb_owner
--

CREATE UNIQUE INDEX index_products_on_sku ON public.products USING btree (sku);


--
-- Name: index_stores_on_active; Type: INDEX; Schema: public; Owner: neondb_owner
--

CREATE INDEX index_stores_on_active ON public.stores USING btree (active);


--
-- Name: index_stores_on_code; Type: INDEX; Schema: public; Owner: neondb_owner
--

CREATE UNIQUE INDEX index_stores_on_code ON public.stores USING btree (code);


--
-- Name: index_switch_jobs_on_order_id; Type: INDEX; Schema: public; Owner: neondb_owner
--

CREATE INDEX index_switch_jobs_on_order_id ON public.switch_jobs USING btree (order_id);


--
-- Name: index_switch_webhooks_on_name_and_store_id; Type: INDEX; Schema: public; Owner: neondb_owner
--

CREATE UNIQUE INDEX index_switch_webhooks_on_name_and_store_id ON public.switch_webhooks USING btree (name, store_id);


--
-- Name: index_switch_webhooks_on_store_id; Type: INDEX; Schema: public; Owner: neondb_owner
--

CREATE INDEX index_switch_webhooks_on_store_id ON public.switch_webhooks USING btree (store_id);


--
-- Name: switch_webhooks fk_rails_163f9d1241; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.switch_webhooks
    ADD CONSTRAINT fk_rails_163f9d1241 FOREIGN KEY (store_id) REFERENCES public.stores(id);


--
-- Name: products fk_rails_277d449bce; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT fk_rails_277d449bce FOREIGN KEY (default_print_flow_id) REFERENCES public.print_flows(id);


--
-- Name: product_print_flows fk_rails_44bedba6e3; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.product_print_flows
    ADD CONSTRAINT fk_rails_44bedba6e3 FOREIGN KEY (print_flow_id) REFERENCES public.print_flows(id);


--
-- Name: product_print_flows fk_rails_53412ea9f8; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.product_print_flows
    ADD CONSTRAINT fk_rails_53412ea9f8 FOREIGN KEY (product_id) REFERENCES public.products(id);


--
-- Name: print_flows fk_rails_69571b5f10; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.print_flows
    ADD CONSTRAINT fk_rails_69571b5f10 FOREIGN KEY (print_webhook_id) REFERENCES public.switch_webhooks(id);


--
-- Name: switch_jobs fk_rails_7e28d7ce9d; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.switch_jobs
    ADD CONSTRAINT fk_rails_7e28d7ce9d FOREIGN KEY (order_id) REFERENCES public.orders(id);


--
-- Name: order_items fk_rails_87cb10ce1f; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT fk_rails_87cb10ce1f FOREIGN KEY (preprint_print_flow_id) REFERENCES public.print_flows(id);


--
-- Name: order_items fk_rails_894c2b1360; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT fk_rails_894c2b1360 FOREIGN KEY (print_machine_id) REFERENCES public.print_machines(id);


--
-- Name: print_flow_machines fk_rails_9c8d0a6216; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.print_flow_machines
    ADD CONSTRAINT fk_rails_9c8d0a6216 FOREIGN KEY (print_machine_id) REFERENCES public.print_machines(id);


--
-- Name: print_flows fk_rails_9f8ca2e144; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.print_flows
    ADD CONSTRAINT fk_rails_9f8ca2e144 FOREIGN KEY (label_webhook_id) REFERENCES public.switch_webhooks(id);


--
-- Name: print_flows fk_rails_e11e0e50a7; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.print_flows
    ADD CONSTRAINT fk_rails_e11e0e50a7 FOREIGN KEY (preprint_webhook_id) REFERENCES public.switch_webhooks(id);


--
-- Name: print_flow_machines fk_rails_e280df2fb8; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.print_flow_machines
    ADD CONSTRAINT fk_rails_e280df2fb8 FOREIGN KEY (print_flow_id) REFERENCES public.print_flows(id);


--
-- Name: order_items fk_rails_e3cb28f071; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT fk_rails_e3cb28f071 FOREIGN KEY (order_id) REFERENCES public.orders(id);


--
-- Name: products fk_rails_efe167855e; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT fk_rails_efe167855e FOREIGN KEY (product_category_id) REFERENCES public.product_categories(id);


--
-- Name: orders fk_rails_f0be2fda72; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT fk_rails_f0be2fda72 FOREIGN KEY (store_id) REFERENCES public.stores(id);


--
-- Name: assets fk_rails_f55f59c4a1; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.assets
    ADD CONSTRAINT fk_rails_f55f59c4a1 FOREIGN KEY (order_item_id) REFERENCES public.order_items(id);


--
-- Name: inventories inventories_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: neondb_owner
--

ALTER TABLE ONLY public.inventories
    ADD CONSTRAINT inventories_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id);


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: cloud_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE cloud_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO neon_superuser WITH GRANT OPTION;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: cloud_admin
--

ALTER DEFAULT PRIVILEGES FOR ROLE cloud_admin IN SCHEMA public GRANT ALL ON TABLES TO neon_superuser WITH GRANT OPTION;


--
-- PostgreSQL database dump complete
--

\unrestrict ROaGTKrdyFhWdx3ArsUjeOZYiUqCPXSqs0veNHMfkoBUzP8MbtMcLEd6eXrwT1v

