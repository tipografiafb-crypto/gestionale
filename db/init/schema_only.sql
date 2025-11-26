--
-- PostgreSQL database dump
--

\restrict BnSFjI8O0ApOECeAiimaVyo9Wzcb9Uov1kitqboh8hhqzYjlG8OWcY764jD9ag7

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
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: assets; Type: TABLE; Schema: public; Owner: -
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


--
-- Name: assets_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.assets_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: assets_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.assets_id_seq OWNED BY public.assets.id;


--
-- Name: inventories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inventories (
    id integer NOT NULL,
    product_id integer NOT NULL,
    quantity_in_stock integer DEFAULT 0,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: inventories_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.inventories_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: inventories_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.inventories_id_seq OWNED BY public.inventories.id;


--
-- Name: order_items; Type: TABLE; Schema: public; Owner: -
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


--
-- Name: order_items_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.order_items_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: order_items_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.order_items_id_seq OWNED BY public.order_items.id;


--
-- Name: orders; Type: TABLE; Schema: public; Owner: -
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


--
-- Name: orders_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.orders_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: orders_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.orders_id_seq OWNED BY public.orders.id;


--
-- Name: print_flow_machines; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.print_flow_machines (
    id bigint NOT NULL,
    print_flow_id bigint NOT NULL,
    print_machine_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: print_flow_machines_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.print_flow_machines_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: print_flow_machines_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.print_flow_machines_id_seq OWNED BY public.print_flow_machines.id;


--
-- Name: print_flows; Type: TABLE; Schema: public; Owner: -
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


--
-- Name: print_flows_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.print_flows_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: print_flows_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.print_flows_id_seq OWNED BY public.print_flows.id;


--
-- Name: print_machines; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.print_machines (
    id bigint NOT NULL,
    name character varying NOT NULL,
    description text,
    active boolean DEFAULT true,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: print_machines_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.print_machines_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: print_machines_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.print_machines_id_seq OWNED BY public.print_machines.id;


--
-- Name: product_categories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.product_categories (
    id bigint NOT NULL,
    name character varying NOT NULL,
    description text,
    active boolean DEFAULT true,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: product_categories_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.product_categories_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: product_categories_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.product_categories_id_seq OWNED BY public.product_categories.id;


--
-- Name: product_print_flows; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.product_print_flows (
    id bigint NOT NULL,
    product_id bigint NOT NULL,
    print_flow_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: product_print_flows_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.product_print_flows_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: product_print_flows_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.product_print_flows_id_seq OWNED BY public.product_print_flows.id;


--
-- Name: products; Type: TABLE; Schema: public; Owner: -
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


--
-- Name: products_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.products_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: products_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.products_id_seq OWNED BY public.products.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: stores; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.stores (
    id bigint NOT NULL,
    code character varying NOT NULL,
    name character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    active boolean DEFAULT true
);


--
-- Name: stores_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.stores_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: stores_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.stores_id_seq OWNED BY public.stores.id;


--
-- Name: switch_jobs; Type: TABLE; Schema: public; Owner: -
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


--
-- Name: switch_jobs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.switch_jobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: switch_jobs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.switch_jobs_id_seq OWNED BY public.switch_jobs.id;


--
-- Name: switch_webhooks; Type: TABLE; Schema: public; Owner: -
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


--
-- Name: switch_webhooks_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.switch_webhooks_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: switch_webhooks_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.switch_webhooks_id_seq OWNED BY public.switch_webhooks.id;


--
-- Name: import_errors; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.import_errors (
    id bigint NOT NULL,
    store_id bigint,
    file_name character varying,
    error_message text,
    import_date timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: import_errors_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.import_errors_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: import_errors_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.import_errors_id_seq OWNED BY public.import_errors.id;


--
-- Name: assets id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assets ALTER COLUMN id SET DEFAULT nextval('public.assets_id_seq'::regclass);


--
-- Name: inventories id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventories ALTER COLUMN id SET DEFAULT nextval('public.inventories_id_seq'::regclass);


--
-- Name: order_items id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_items ALTER COLUMN id SET DEFAULT nextval('public.order_items_id_seq'::regclass);


--
-- Name: orders id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders ALTER COLUMN id SET DEFAULT nextval('public.orders_id_seq'::regclass);


--
-- Name: print_flow_machines id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.print_flow_machines ALTER COLUMN id SET DEFAULT nextval('public.print_flow_machines_id_seq'::regclass);


--
-- Name: print_flows id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.print_flows ALTER COLUMN id SET DEFAULT nextval('public.print_flows_id_seq'::regclass);


--
-- Name: print_machines id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.print_machines ALTER COLUMN id SET DEFAULT nextval('public.print_machines_id_seq'::regclass);


--
-- Name: product_categories id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_categories ALTER COLUMN id SET DEFAULT nextval('public.product_categories_id_seq'::regclass);


--
-- Name: product_print_flows id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_print_flows ALTER COLUMN id SET DEFAULT nextval('public.product_print_flows_id_seq'::regclass);


--
-- Name: products id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products ALTER COLUMN id SET DEFAULT nextval('public.products_id_seq'::regclass);


--
-- Name: stores id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stores ALTER COLUMN id SET DEFAULT nextval('public.stores_id_seq'::regclass);


--
-- Name: switch_jobs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.switch_jobs ALTER COLUMN id SET DEFAULT nextval('public.switch_jobs_id_seq'::regclass);


--
-- Name: switch_webhooks id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.switch_webhooks ALTER COLUMN id SET DEFAULT nextval('public.switch_webhooks_id_seq'::regclass);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: assets assets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assets
    ADD CONSTRAINT assets_pkey PRIMARY KEY (id);


--
-- Name: inventories inventories_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventories
    ADD CONSTRAINT inventories_pkey PRIMARY KEY (id);


--
-- Name: inventories inventories_product_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventories
    ADD CONSTRAINT inventories_product_id_key UNIQUE (product_id);


--
-- Name: order_items order_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT order_items_pkey PRIMARY KEY (id);


--
-- Name: orders orders_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_pkey PRIMARY KEY (id);


--
-- Name: print_flow_machines print_flow_machines_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.print_flow_machines
    ADD CONSTRAINT print_flow_machines_pkey PRIMARY KEY (id);


--
-- Name: print_flows print_flows_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.print_flows
    ADD CONSTRAINT print_flows_pkey PRIMARY KEY (id);


--
-- Name: print_machines print_machines_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.print_machines
    ADD CONSTRAINT print_machines_pkey PRIMARY KEY (id);


--
-- Name: product_categories product_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_categories
    ADD CONSTRAINT product_categories_pkey PRIMARY KEY (id);


--
-- Name: product_print_flows product_print_flows_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_print_flows
    ADD CONSTRAINT product_print_flows_pkey PRIMARY KEY (id);


--
-- Name: products products_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: stores stores_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stores
    ADD CONSTRAINT stores_pkey PRIMARY KEY (id);


--
-- Name: switch_jobs switch_jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.switch_jobs
    ADD CONSTRAINT switch_jobs_pkey PRIMARY KEY (id);


--
-- Name: switch_webhooks switch_webhooks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.switch_webhooks
    ADD CONSTRAINT switch_webhooks_pkey PRIMARY KEY (id);


--
-- Name: index_assets_on_order_item_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_assets_on_order_item_id ON public.assets USING btree (order_item_id);


--
-- Name: index_order_items_on_order_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_order_items_on_order_id ON public.order_items USING btree (order_id);


--
-- Name: index_order_items_on_preprint_print_flow_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_order_items_on_preprint_print_flow_id ON public.order_items USING btree (preprint_print_flow_id);


--
-- Name: index_order_items_on_preprint_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_order_items_on_preprint_status ON public.order_items USING btree (preprint_status);


--
-- Name: index_order_items_on_print_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_order_items_on_print_status ON public.order_items USING btree (print_status);


--
-- Name: index_orders_on_store_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_orders_on_store_id ON public.orders USING btree (store_id);


--
-- Name: index_orders_on_store_id_and_external_order_code; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_orders_on_store_id_and_external_order_code ON public.orders USING btree (store_id, external_order_code);


--
-- Name: index_print_flow_machines_on_print_flow_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_print_flow_machines_on_print_flow_id ON public.print_flow_machines USING btree (print_flow_id);


--
-- Name: index_print_flow_machines_on_print_flow_id_and_print_machine_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_print_flow_machines_on_print_flow_id_and_print_machine_id ON public.print_flow_machines USING btree (print_flow_id, print_machine_id);


--
-- Name: index_print_flow_machines_on_print_machine_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_print_flow_machines_on_print_machine_id ON public.print_flow_machines USING btree (print_machine_id);


--
-- Name: index_print_flows_on_label_webhook_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_print_flows_on_label_webhook_id ON public.print_flows USING btree (label_webhook_id);


--
-- Name: index_print_flows_on_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_print_flows_on_name ON public.print_flows USING btree (name);


--
-- Name: index_print_flows_on_preprint_webhook_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_print_flows_on_preprint_webhook_id ON public.print_flows USING btree (preprint_webhook_id);


--
-- Name: index_print_flows_on_print_webhook_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_print_flows_on_print_webhook_id ON public.print_flows USING btree (print_webhook_id);


--
-- Name: index_print_machines_on_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_print_machines_on_name ON public.print_machines USING btree (name);


--
-- Name: index_product_categories_on_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_product_categories_on_name ON public.product_categories USING btree (name);


--
-- Name: index_product_print_flows_on_print_flow_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_product_print_flows_on_print_flow_id ON public.product_print_flows USING btree (print_flow_id);


--
-- Name: index_product_print_flows_on_product_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_product_print_flows_on_product_id ON public.product_print_flows USING btree (product_id);


--
-- Name: index_product_print_flows_on_product_id_and_print_flow_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_product_print_flows_on_product_id_and_print_flow_id ON public.product_print_flows USING btree (product_id, print_flow_id);


--
-- Name: index_products_on_default_print_flow_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_products_on_default_print_flow_id ON public.products USING btree (default_print_flow_id);


--
-- Name: index_products_on_product_category_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_products_on_product_category_id ON public.products USING btree (product_category_id);


--
-- Name: index_products_on_sku; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_products_on_sku ON public.products USING btree (sku);


--
-- Name: index_stores_on_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_stores_on_active ON public.stores USING btree (active);


--
-- Name: index_stores_on_code; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_stores_on_code ON public.stores USING btree (code);


--
-- Name: index_switch_jobs_on_order_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_switch_jobs_on_order_id ON public.switch_jobs USING btree (order_id);


--
-- Name: index_switch_webhooks_on_name_and_store_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_switch_webhooks_on_name_and_store_id ON public.switch_webhooks USING btree (name, store_id);


--
-- Name: index_switch_webhooks_on_store_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_switch_webhooks_on_store_id ON public.switch_webhooks USING btree (store_id);


--
-- Name: switch_webhooks fk_rails_163f9d1241; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.switch_webhooks
    ADD CONSTRAINT fk_rails_163f9d1241 FOREIGN KEY (store_id) REFERENCES public.stores(id);


--
-- Name: products fk_rails_277d449bce; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT fk_rails_277d449bce FOREIGN KEY (default_print_flow_id) REFERENCES public.print_flows(id);


--
-- Name: product_print_flows fk_rails_44bedba6e3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_print_flows
    ADD CONSTRAINT fk_rails_44bedba6e3 FOREIGN KEY (print_flow_id) REFERENCES public.print_flows(id);


--
-- Name: product_print_flows fk_rails_53412ea9f8; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.product_print_flows
    ADD CONSTRAINT fk_rails_53412ea9f8 FOREIGN KEY (product_id) REFERENCES public.products(id);


--
-- Name: print_flows fk_rails_69571b5f10; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.print_flows
    ADD CONSTRAINT fk_rails_69571b5f10 FOREIGN KEY (print_webhook_id) REFERENCES public.switch_webhooks(id);


--
-- Name: switch_jobs fk_rails_7e28d7ce9d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.switch_jobs
    ADD CONSTRAINT fk_rails_7e28d7ce9d FOREIGN KEY (order_id) REFERENCES public.orders(id);


--
-- Name: order_items fk_rails_87cb10ce1f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT fk_rails_87cb10ce1f FOREIGN KEY (preprint_print_flow_id) REFERENCES public.print_flows(id);


--
-- Name: order_items fk_rails_894c2b1360; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT fk_rails_894c2b1360 FOREIGN KEY (print_machine_id) REFERENCES public.print_machines(id);


--
-- Name: print_flow_machines fk_rails_9c8d0a6216; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.print_flow_machines
    ADD CONSTRAINT fk_rails_9c8d0a6216 FOREIGN KEY (print_machine_id) REFERENCES public.print_machines(id);


--
-- Name: print_flows fk_rails_9f8ca2e144; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.print_flows
    ADD CONSTRAINT fk_rails_9f8ca2e144 FOREIGN KEY (label_webhook_id) REFERENCES public.switch_webhooks(id);


--
-- Name: print_flows fk_rails_e11e0e50a7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.print_flows
    ADD CONSTRAINT fk_rails_e11e0e50a7 FOREIGN KEY (preprint_webhook_id) REFERENCES public.switch_webhooks(id);


--
-- Name: print_flow_machines fk_rails_e280df2fb8; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.print_flow_machines
    ADD CONSTRAINT fk_rails_e280df2fb8 FOREIGN KEY (print_flow_id) REFERENCES public.print_flows(id);


--
-- Name: order_items fk_rails_e3cb28f071; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT fk_rails_e3cb28f071 FOREIGN KEY (order_id) REFERENCES public.orders(id);


--
-- Name: products fk_rails_efe167855e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT fk_rails_efe167855e FOREIGN KEY (product_category_id) REFERENCES public.product_categories(id);


--
-- Name: orders fk_rails_f0be2fda72; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT fk_rails_f0be2fda72 FOREIGN KEY (store_id) REFERENCES public.stores(id);


--
-- Name: assets fk_rails_f55f59c4a1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assets
    ADD CONSTRAINT fk_rails_f55f59c4a1 FOREIGN KEY (order_item_id) REFERENCES public.order_items(id);


--
-- Name: inventories inventories_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inventories
    ADD CONSTRAINT inventories_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id);


--
-- PostgreSQL database dump complete
--

\unrestrict BnSFjI8O0ApOECeAiimaVyo9Wzcb9Uov1kitqboh8hhqzYjlG8OWcY764jD9ag7

