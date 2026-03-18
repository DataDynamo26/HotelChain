import streamlit as st
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
import numpy as np
from datetime import datetime, timedelta

# ── Page Config ───────────────────────────────────────────────────────────────
st.set_page_config(
    page_title="StaySphere Analytics",
    page_icon="🏨",
    layout="wide",
    initial_sidebar_state="expanded"
)

# ── Custom CSS ────────────────────────────────────────────────────────────────
st.markdown("""
<style>
@import url('https://fonts.googleapis.com/css2?family=Syne:wght@400;600;700;800&family=DM+Sans:wght@300;400;500&display=swap');
html, body, [class*="css"] { font-family: 'DM Sans', sans-serif; }
.stApp { background: #0a0e1a; }
section[data-testid="stSidebar"] { background: #0d1220 !important; border-right: 1px solid #1e2a45; }
.main-title { font-family: 'Syne', sans-serif; font-weight: 800; font-size: 2.6rem;
    background: linear-gradient(135deg, #00d4ff 0%, #7c3aed 50%, #ff6b6b 100%);
    -webkit-background-clip: text; -webkit-text-fill-color: transparent;
    background-clip: text; letter-spacing: -1px; }
.subtitle { font-family: 'DM Sans', sans-serif; font-weight: 300; font-size: 0.85rem;
    color: #4a6080; letter-spacing: 2px; text-transform: uppercase; margin-top: 4px; }
.kpi-card { background: linear-gradient(135deg, #0d1220 0%, #121929 100%);
    border: 1px solid #1e2a45; border-radius: 16px; padding: 20px 24px;
    position: relative; overflow: hidden; }
.kpi-card::before { content: ''; position: absolute; top: 0; left: 0; right: 0; height: 2px;
    background: var(--accent, linear-gradient(90deg, #00d4ff, #7c3aed)); }
.kpi-label { font-size: 0.70rem; font-weight: 500; color: #4a6080;
    text-transform: uppercase; letter-spacing: 1.5px; margin-bottom: 8px; }
.kpi-value { font-family: 'Syne', sans-serif; font-size: 2.1rem; font-weight: 700;
    color: #e8f4ff; line-height: 1; margin-bottom: 4px; }
.kpi-delta { font-size: 0.75rem; font-weight: 500; color: #22c55e; }
.kpi-delta.neg { color: #ef4444; }
.section-title { font-family: 'Syne', sans-serif; font-weight: 700; font-size: 1rem;
    color: #c8daf0; margin-bottom: 14px; padding-bottom: 8px;
    border-bottom: 1px solid #1e2a45; }
.alert-box { background: rgba(239,68,68,0.08); border: 1px solid rgba(239,68,68,0.3);
    border-left: 3px solid #ef4444; border-radius: 8px; padding: 12px 16px;
    margin: 6px 0; font-size: 0.84rem; color: #fca5a5; }
.success-box { background: rgba(34,197,94,0.08); border: 1px solid rgba(34,197,94,0.25);
    border-left: 3px solid #22c55e; border-radius: 8px; padding: 12px 16px;
    margin: 6px 0; font-size: 0.84rem; color: #86efac; }
.stTabs [data-baseweb="tab-list"] { background: #0d1220; border-bottom: 1px solid #1e2a45; gap: 4px; }
.stTabs [data-baseweb="tab"] { font-family: 'Syne', sans-serif; font-weight: 600;
    font-size: 0.80rem; color: #4a6080; letter-spacing: 0.5px;
    padding: 10px 18px; border-radius: 8px 8px 0 0; }
.stTabs [aria-selected="true"] { color: #00d4ff !important;
    background: rgba(0,212,255,0.06) !important;
    border-bottom: 2px solid #00d4ff !important; }
div[data-testid="stMetricValue"] { font-family: 'Syne', sans-serif !important; color: #e8f4ff !important; }
div[data-testid="stMetricLabel"] { color: #4a6080 !important; font-size: 0.72rem !important;
    text-transform: uppercase; letter-spacing: 1px; }
div[data-testid="stMarkdownContainer"] p { color: #8aa4c0; }
</style>
""", unsafe_allow_html=True)

# ── Chart helper ──────────────────────────────────────────────────────────────
def sc(fig, h=320):
    fig.update_layout(
        paper_bgcolor="rgba(0,0,0,0)", plot_bgcolor="rgba(0,0,0,0)",
        font=dict(color="#8aa4c0", family="DM Sans", size=11),
        height=h, margin=dict(l=10, r=10, t=30, b=10),
        legend=dict(bgcolor="rgba(0,0,0,0)", bordercolor="#1e2a45", borderwidth=1),
        xaxis=dict(gridcolor="#1e2a45", linecolor="#1e2a45", tickcolor="#4a6080"),
        yaxis=dict(gridcolor="#1e2a45", linecolor="#1e2a45", tickcolor="#4a6080"),
        colorway=["#00d4ff","#7c3aed","#ff6b6b","#22c55e","#f59e0b","#ec4899"]
    )
    return fig

# ── Demo Data ─────────────────────────────────────────────────────────────────
@st.cache_data
def demo():
    np.random.seed(42)
    n = 50
    start = datetime(2024, 1, 1)
    hotels = ["H001","H002","H003","H004","H005"]
    tiers  = ["Bronze","Silver","Gold","Platinum"]

    guests = pd.DataFrame({
        "guest_id":    [f"G{1000+i}" for i in range(n)],
        "loyalty_tier": np.random.choice(tiers, n, p=[0.35,0.30,0.25,0.10]),
        "country":      np.random.choice(["India","USA","UK","Australia","UAE"], n),
        "city":         np.random.choice(["Mumbai","Delhi","Bangalore","Hyderabad","Chennai"], n),
    })

    check_ins  = [start + timedelta(days=int(x)) for x in np.random.randint(0,365,n)]
    stays      = np.random.randint(1,10,n)
    check_outs = [ci+timedelta(days=int(s)) for ci,s in zip(check_ins,stays)]

    reservations = pd.DataFrame({
        "reservation_id":       [f"R{2000+i}" for i in range(n)],
        "guest_id":             [f"G{1000+i}" for i in range(n)],
        "room_id":              np.random.choice([f"{300+i}" for i in range(50)],n),
        "hotel_id":             np.random.choice(hotels,n),
        "check_in_date":        check_ins,
        "check_out_date":       check_outs,
        "length_of_stay":       stays,
        "booking_channel":      np.random.choice(["Website","Mobile App","OTA","Corporate","Walk-in"],n,p=[0.30,0.25,0.25,0.15,0.05]),
        "status":               np.random.choice(["confirmed","cancelled","completed"],n,p=[0.35,0.15,0.50]),
        "is_double_booked":     np.random.choice([True,False],n,p=[0.05,0.95]),
        "is_suspicious_cancel": np.random.choice([True,False],n,p=[0.04,0.96]),
    })

    rooms = pd.DataFrame({
        "room_id":    [f"{300+i}" for i in range(50)],
        "hotel_id":   np.random.choice(hotels,50),
        "room_type":  np.random.choice(["Standard","Deluxe","Suite"],50,p=[0.45,0.40,0.15]),
        "capacity":   np.random.choice([2,2,4],50),
        "base_price": np.random.choice([80,100,120,150,200,250,300],50),
        "status":     np.random.choice(["Available","Occupied","Maintenance"],50,p=[0.50,0.40,0.10]),
    })

    task_types = np.random.choice(["cleaning","maintenance"],n,p=[0.70,0.30])
    durations,sla_flags = [],[]
    for t in task_types:
        if t=="cleaning":
            d=max(10,min(90,int(np.random.normal(40,15)))); durations.append(d); sla_flags.append(d>45)
        else:
            d=max(20,min(200,int(np.random.normal(100,40)))); durations.append(d); sla_flags.append(d>120)

    housekeeping = pd.DataFrame({
        "task_id":           [f"T{4000+i}" for i in range(n)],
        "room_id":           np.random.choice([f"{300+i}" for i in range(50)],n),
        "hotel_id":          np.random.choice(hotels,n),
        "task_type":         task_types,
        "assigned_staff":    np.random.choice(["Ravi Kumar","Priya Nair","John Doe","Amit Singh","Sunita Rao"],n),
        "duration_minutes":  durations,
        "sla_breached":      sla_flags,
        "issue_detected_flag": np.random.choice([True,False],n,p=[0.20,0.80]),
        "status":            np.random.choice(["Completed","Pending","In Progress"],n,p=[0.80,0.10,0.10]),
    })

    amounts   = np.random.uniform(200,1500,n).round(2)
    taxes     = (amounts*0.10).round(2)
    discounts = np.random.choice([0,20,50,100],n,p=[0.6,0.2,0.15,0.05])
    billing   = pd.DataFrame({
        "bill_id":          [f"B{5000+i}" for i in range(n)],
        "reservation_id":   [f"R{2000+i}" for i in range(n)],
        "guest_id":         [f"G{1000+i}" for i in range(n)],
        "total_amount":     amounts,
        "taxes":            taxes,
        "discounts":        discounts,
        "net_amount":       (amounts-discounts+taxes).round(2),
        "payment_mode":     np.random.choice(["Credit Card","UPI","Cash","Net Banking","Debit Card"],n,p=[0.40,0.30,0.10,0.10,0.10]),
        "is_flagged":       np.random.choice([True,False],n,p=[0.08,0.92]),
        "billing_mismatch": np.random.choice([True,False],n,p=[0.05,0.95]),
        "payment_time":     [start+timedelta(days=int(x)) for x in np.random.randint(0,365,n)],
    })
    return guests, reservations, rooms, housekeeping, billing

# ── Load Data ─────────────────────────────────────────────────────────────────
try:
    from snowflake_conn import run_query
    guests       = run_query("SELECT * FROM RAW_DB.GOLD.DIM_GUEST WHERE IS_CURRENT=TRUE")
    reservations = run_query("SELECT * FROM RAW_DB.GOLD.FACT_RESERVATION")
    rooms        = run_query("SELECT * FROM RAW_DB.GOLD.DIM_ROOM WHERE IS_CURRENT=TRUE")
    housekeeping = run_query("SELECT * FROM RAW_DB.GOLD.FACT_HOUSEKEEPING")
    billing      = run_query("SELECT * FROM RAW_DB.GOLD.FACT_BILLING")
    for df in [guests,reservations,rooms,housekeeping,billing]:
        df.columns = df.columns.str.lower()
    data_source = "Snowflake Gold Layer"
except Exception:
    guests, reservations, rooms, housekeeping, billing = demo()
    data_source = "Demo Data (Snowflake not connected)"

# ── SIDEBAR ───────────────────────────────────────────────────────────────────
with st.sidebar:
    st.markdown("""<div style='padding:20px 0 10px;'>
        <div style='font-family:Syne,sans-serif;font-weight:800;font-size:1.4rem;color:#00d4ff;'>STAYSPHERE</div>
        <div style='font-size:0.62rem;color:#4a6080;letter-spacing:2px;text-transform:uppercase;margin-top:2px;'>Hotel Analytics Platform</div>
    </div>""", unsafe_allow_html=True)
    st.markdown("---")

    hotels_list   = ["All Hotels","H001","H002","H003","H004","H005"]
    sel_hotel     = st.selectbox("Hotel", hotels_list)
    tier_opts     = ["Bronze","Silver","Gold","Platinum"]
    sel_tiers     = st.multiselect("Loyalty Tier", tier_opts, default=tier_opts)
    chan_opts      = reservations["booking_channel"].unique().tolist()
    sel_channels  = st.multiselect("Booking Channel", chan_opts, default=chan_opts)

    st.markdown("---")
    st.markdown(f'<div style="font-size:0.68rem;color:#4a6080;">Source: {data_source}</div>', unsafe_allow_html=True)
    if st.button("🔄 Refresh Data", use_container_width=True):
        st.cache_data.clear(); st.rerun()

# ── Filters ───────────────────────────────────────────────────────────────────
res_f = reservations.copy()
if sel_hotel != "All Hotels":
    res_f = res_f[res_f["hotel_id"] == sel_hotel]
if sel_channels:
    res_f = res_f[res_f["booking_channel"].isin(sel_channels)]
guests_f = guests[guests["loyalty_tier"].isin(sel_tiers)] if sel_tiers else guests.copy()

# ── KPI CALCULATIONS ──────────────────────────────────────────────────────────
total_res     = len(res_f)
total_rev     = billing["total_amount"].sum()
cancels       = len(res_f[res_f["status"]=="cancelled"])
occ_rate      = round(100*len(res_f[res_f["status"]!="cancelled"])/max(len(rooms),1),1)
revpar        = round(total_rev/max(len(rooms),1),2)
sla_pct       = round(100*(1-housekeeping["sla_breached"].mean()),1)
billing_acc   = round(1-(billing["is_flagged"].sum()/max(len(billing),1)),4)
completed     = len(res_f[res_f["status"]=="completed"])
conv_pct      = round(100*completed/max(total_res,1),2)

# ── HEADER ────────────────────────────────────────────────────────────────────
st.markdown('<div class="main-title">Hotel Operations Dashboard</div>', unsafe_allow_html=True)
st.markdown('<div class="subtitle">StaySphere · Snowflake Medallion Architecture · Bronze → Silver → Gold</div>', unsafe_allow_html=True)
st.markdown("<br>", unsafe_allow_html=True)

# ── KPI CARDS ─────────────────────────────────────────────────────────────────
c1,c2,c3,c4,c5,c6 = st.columns(6)
kpis = [
    (c1,"Total Reservations",  f"{total_res:,}",    "KPI 2 · Conversion",       "linear-gradient(90deg,#00d4ff,#0ea5e9)",""),
    (c2,"Total Revenue",       f"₹{total_rev:,.0f}","KPI 4 · RevPAR ₹"+f"{revpar:,.0f}","linear-gradient(90deg,#7c3aed,#a855f7)",""),
    (c3,"Occupancy Rate",      f"{occ_rate}%",      "KPI 1 · Room Occupancy",   "linear-gradient(90deg,#22c55e,#16a34a)",""),
    (c4,"SLA Compliance",      f"{sla_pct}%",       "KPI 3 · Housekeeping",     "linear-gradient(90deg,#f59e0b,#d97706)",""),
    (c5,"Billing Accuracy",    f"{billing_acc:.4f}","KPI 5 · Accuracy Index",   "linear-gradient(90deg,#ec4899,#db2777)",""),
    (c6,"Cancellations",       f"{cancels}",        f"{round(100*cancels/max(total_res,1),1)}% cancel rate","linear-gradient(90deg,#ff6b6b,#ef4444)","neg" if cancels>5 else ""),
]
for col,label,value,delta,accent,neg in kpis:
    with col:
        st.markdown(f"""<div class="kpi-card" style="--accent:{accent};">
            <div class="kpi-label">{label}</div>
            <div class="kpi-value">{value}</div>
            <div class="kpi-delta {neg}">{delta}</div>
        </div>""", unsafe_allow_html=True)

st.markdown("<br>", unsafe_allow_html=True)

# ── TABS ──────────────────────────────────────────────────────────────────────
t1,t2,t3,t4,t5,t6 = st.tabs([
    "📊  Overview","🛏️  Reservations","🧹  Housekeeping",
    "💳  Billing & Fraud","⚠️  Anomalies","📋  KPI Summary"
])

# ════════════════════════════
# TAB 1 — OVERVIEW
# ════════════════════════════
with t1:
    cl, cr = st.columns([3,2])
    with cl:
        st.markdown('<div class="section-title">Monthly Booking Volume</div>', unsafe_allow_html=True)
        if "check_in_date" in res_f.columns:
            trend = (res_f.groupby(pd.to_datetime(res_f["check_in_date"]).dt.to_period("M").astype(str))
                     .size().reset_index(name="bookings"))
            fig = px.area(trend, x="check_in_date", y="bookings")
            fig.update_traces(fill="tozeroy", line_color="#00d4ff", fillcolor="rgba(0,212,255,0.08)")
            st.plotly_chart(sc(fig,300), use_container_width=True)

    with cr:
        st.markdown('<div class="section-title">Loyalty Tier Distribution</div>', unsafe_allow_html=True)
        tc = guests_f["loyalty_tier"].value_counts().reset_index()
        tc.columns = ["tier","count"]
        fig2 = px.pie(tc, names="tier", values="count", hole=0.55,
                      color_discrete_sequence=["#00d4ff","#7c3aed","#22c55e","#f59e0b"])
        st.plotly_chart(sc(fig2,300), use_container_width=True)

    ca,cb,cc = st.columns(3)
    with ca:
        st.markdown('<div class="section-title">Bookings by Channel</div>', unsafe_allow_html=True)
        ch = res_f["booking_channel"].value_counts().reset_index()
        ch.columns = ["channel","count"]
        fig3 = px.bar(ch, x="count", y="channel", orientation="h",
                      color="count", color_continuous_scale=["#1e2a45","#00d4ff"])
        fig3.update_coloraxes(showscale=False)
        st.plotly_chart(sc(fig3,260), use_container_width=True)

    with cb:
        st.markdown('<div class="section-title">Room Type Split</div>', unsafe_allow_html=True)
        rt = rooms["room_type"].value_counts().reset_index()
        rt.columns = ["type","count"]
        fig4 = px.bar(rt, x="type", y="count", color="type",
                      color_discrete_sequence=["#7c3aed","#00d4ff","#ff6b6b"])
        st.plotly_chart(sc(fig4,260), use_container_width=True)

    with cc:
        st.markdown('<div class="section-title">Room Status</div>', unsafe_allow_html=True)
        rs = rooms["status"].value_counts().reset_index()
        rs.columns = ["status","count"]
        fig5 = px.pie(rs, names="status", values="count", hole=0.5,
                      color_discrete_map={"Available":"#22c55e","Occupied":"#f59e0b","Maintenance":"#ef4444"})
        st.plotly_chart(sc(fig5,260), use_container_width=True)

# ════════════════════════════
# TAB 2 — RESERVATIONS
# ════════════════════════════
with t2:
    r1,r2 = st.columns(2)
    with r1:
        st.markdown('<div class="section-title">Reservation Status</div>', unsafe_allow_html=True)
        sc_df = res_f["status"].value_counts().reset_index()
        sc_df.columns = ["status","count"]
        fig = px.bar(sc_df, x="status", y="count", color="status",
                     color_discrete_map={"completed":"#22c55e","confirmed":"#00d4ff","cancelled":"#ef4444"})
        st.plotly_chart(sc(fig), use_container_width=True)

    with r2:
        st.markdown('<div class="section-title">Length of Stay Distribution</div>', unsafe_allow_html=True)
        los = res_f["length_of_stay"].value_counts().reset_index().sort_values("length_of_stay")
        los.columns = ["nights","count"]
        fig2 = px.bar(los, x="nights", y="count", color="count",
                      color_continuous_scale=["#1e2a45","#7c3aed","#00d4ff"])
        fig2.update_coloraxes(showscale=False)
        st.plotly_chart(sc(fig2), use_container_width=True)

    st.markdown('<div class="section-title">Revenue by Booking Channel</div>', unsafe_allow_html=True)
    rev_ch = (res_f.merge(billing[["reservation_id","total_amount"]],on="reservation_id",how="left")
              .groupby("booking_channel").agg(revenue=("total_amount","sum"),bookings=("reservation_id","count"))
              .reset_index().sort_values("revenue",ascending=False))
    fig3 = px.bar(rev_ch, x="booking_channel", y="revenue",
                  color="bookings", color_continuous_scale=["#1e2a45","#7c3aed"], text="bookings")
    fig3.update_traces(texttemplate="<b>%{text}</b>", textposition="outside", textfont_color="#8aa4c0")
    st.plotly_chart(sc(fig3,260), use_container_width=True)

    st.markdown('<div class="section-title">All Reservations</div>', unsafe_allow_html=True)
    show_cols = [c for c in ["reservation_id","guest_id","room_id","hotel_id","check_in_date",
                              "check_out_date","length_of_stay","booking_channel","status"] if c in res_f.columns]
    st.dataframe(res_f[show_cols].sort_values("check_in_date",ascending=False),
                 use_container_width=True, height=280)

# ════════════════════════════
# TAB 3 — HOUSEKEEPING
# ════════════════════════════
with t3:
    h1c,h2c = st.columns(2)
    with h1c:
        st.markdown('<div class="section-title">SLA Performance by Task Type</div>', unsafe_allow_html=True)
        sla_s = (housekeeping.groupby("task_type")
                 .agg(total=("task_id","count"), breaches=("sla_breached","sum")).reset_index())
        fig = go.Figure()
        fig.add_trace(go.Bar(name="Passed",  x=sla_s["task_type"],
                             y=sla_s["total"]-sla_s["breaches"], marker_color="#22c55e"))
        fig.add_trace(go.Bar(name="Breached",x=sla_s["task_type"],
                             y=sla_s["breaches"], marker_color="#ef4444"))
        fig.update_layout(barmode="stack")
        st.plotly_chart(sc(fig), use_container_width=True)

    with h2c:
        st.markdown('<div class="section-title">Duration Distribution vs SLA Threshold</div>', unsafe_allow_html=True)
        fig2 = px.histogram(housekeeping, x="duration_minutes", color="task_type", nbins=20,
                            color_discrete_map={"cleaning":"#00d4ff","maintenance":"#7c3aed"}, barmode="overlay")
        fig2.add_vline(x=45,  line_dash="dash", line_color="#22c55e",
                       annotation_text="Cleaning SLA (45m)", annotation_font_color="#22c55e")
        fig2.add_vline(x=120, line_dash="dash", line_color="#f59e0b",
                       annotation_text="Maint SLA (120m)", annotation_font_color="#f59e0b")
        st.plotly_chart(sc(fig2), use_container_width=True)

    ha,hb = st.columns(2)
    with ha:
        st.markdown('<div class="section-title">Staff Performance</div>', unsafe_allow_html=True)
        staff = (housekeeping.groupby("assigned_staff")
                 .agg(tasks=("task_id","count"), avg_dur=("duration_minutes","mean"),
                      issues=("issue_detected_flag","sum"), breaches=("sla_breached","sum"))
                 .reset_index())
        staff["avg_dur"] = staff["avg_dur"].round(1)
        st.dataframe(staff.sort_values("tasks",ascending=False), use_container_width=True, height=220)

    with hb:
        st.markdown('<div class="section-title">Issue Detection by Hotel</div>', unsafe_allow_html=True)
        hi = (housekeeping.groupby("hotel_id")
              .agg(issues=("issue_detected_flag","sum"), total=("task_id","count")).reset_index())
        hi["issue_pct"] = round(100*hi["issues"]/hi["total"],1)
        fig3 = px.bar(hi, x="hotel_id", y="issue_pct", color="issue_pct",
                      color_continuous_scale=["#22c55e","#f59e0b","#ef4444"], text="issue_pct")
        fig3.update_traces(texttemplate="%{text}%", textposition="outside", textfont_color="#8aa4c0")
        fig3.update_coloraxes(showscale=False)
        st.plotly_chart(sc(fig3,220), use_container_width=True)

# ════════════════════════════
# TAB 4 — BILLING & FRAUD
# ════════════════════════════
with t4:
    b1,b2,b3,b4 = st.columns(4)
    b1.metric("Total Bills",     f"{len(billing):,}")
    b2.metric("Total Revenue",   f"₹{billing['total_amount'].sum():,.0f}")
    b3.metric("Flagged Bills",   int(billing["is_flagged"].sum()))
    b4.metric("Billing Accuracy",f"{billing_acc:.4f}")

    st.markdown("<br>", unsafe_allow_html=True)
    ba,bb = st.columns(2)

    with ba:
        st.markdown('<div class="section-title">Revenue by Payment Mode</div>', unsafe_allow_html=True)
        pay = (billing.groupby("payment_mode").agg(revenue=("total_amount","sum")).reset_index()
               .sort_values("revenue",ascending=False))
        fig = px.bar(pay, x="payment_mode", y="revenue", color="payment_mode",
                     color_discrete_sequence=["#00d4ff","#7c3aed","#22c55e","#f59e0b","#ff6b6b"])
        st.plotly_chart(sc(fig), use_container_width=True)

    with bb:
        st.markdown('<div class="section-title">Bill Amount Distribution</div>', unsafe_allow_html=True)
        fig2 = px.histogram(billing, x="total_amount", nbins=20,
                            color_discrete_sequence=["#7c3aed"])
        fig2.update_traces(opacity=0.85)
        st.plotly_chart(sc(fig2), use_container_width=True)

    st.markdown('<div class="section-title">Flagged Transactions</div>', unsafe_allow_html=True)
    flagged = billing[billing["is_flagged"]==True]
    if len(flagged)>0:
        st.markdown(f'<div class="alert-box">⚠️ {len(flagged)} flagged transactions detected</div>',
                    unsafe_allow_html=True)
        st.dataframe(flagged[["bill_id","reservation_id","guest_id","total_amount",
                                "payment_mode","is_flagged"]].reset_index(drop=True),
                     use_container_width=True, height=220)
    else:
        st.markdown('<div class="success-box">✅ No flagged transactions</div>', unsafe_allow_html=True)

    st.markdown('<div class="section-title">All Billing Records</div>', unsafe_allow_html=True)
    st.dataframe(billing[["bill_id","reservation_id","total_amount","taxes",
                            "discounts","net_amount","payment_mode","is_flagged"]]
                 .sort_values("total_amount",ascending=False),
                 use_container_width=True, height=250)

# ════════════════════════════
# TAB 5 — ANOMALIES
# ════════════════════════════
with t5:
    aa,ab,ac,ad = st.columns(4)
    dbl  = int(reservations.get("is_double_booked",    pd.Series([False]*len(reservations))).sum())
    sus  = int(reservations.get("is_suspicious_cancel",pd.Series([False]*len(reservations))).sum())
    slab = int(housekeeping["sla_breached"].sum())
    mis  = int(billing.get("billing_mismatch",          pd.Series([False]*len(billing))).sum())
    aa.metric("Double Bookings",    dbl)
    ab.metric("Suspicious Cancels", sus)
    ac.metric("SLA Breaches",       slab)
    ad.metric("Billing Mismatches", mis)

    st.markdown("<br>", unsafe_allow_html=True)
    an1,an2 = st.columns(2)

    with an1:
        st.markdown('<div class="section-title">Double Booking Alerts</div>', unsafe_allow_html=True)
        if "is_double_booked" in reservations.columns:
            db = reservations[reservations["is_double_booked"]==True]
            if len(db)>0:
                st.markdown(f'<div class="alert-box">🔴 {len(db)} double-booking conflicts</div>',
                            unsafe_allow_html=True)
                st.dataframe(db[["reservation_id","guest_id","room_id",
                                  "check_in_date","check_out_date","status"]],
                             use_container_width=True, height=200)
            else:
                st.markdown('<div class="success-box">✅ No double bookings</div>', unsafe_allow_html=True)

    with an2:
        st.markdown('<div class="section-title">Suspicious Cancellations</div>', unsafe_allow_html=True)
        if "is_suspicious_cancel" in reservations.columns:
            scd = reservations[reservations["is_suspicious_cancel"]==True]
            if len(scd)>0:
                st.markdown(f'<div class="alert-box">⚠️ {len(scd)} suspicious patterns</div>',
                            unsafe_allow_html=True)
                st.dataframe(scd[["reservation_id","guest_id","check_in_date","status"]],
                             use_container_width=True, height=200)
            else:
                st.markdown('<div class="success-box">✅ No suspicious cancellations</div>',
                            unsafe_allow_html=True)

    st.markdown('<div class="section-title">SLA Breach Detail</div>', unsafe_allow_html=True)
    sla_d = housekeeping[housekeeping["sla_breached"]==True]
    if len(sla_d)>0:
        st.markdown(f'<div class="alert-box">🔴 {len(sla_d)} tasks exceeded SLA</div>',
                    unsafe_allow_html=True)
        st.dataframe(sla_d[["task_id","room_id","hotel_id","task_type",
                              "assigned_staff","duration_minutes","status"]],
                     use_container_width=True, height=240)
    else:
        st.markdown('<div class="success-box">✅ All tasks within SLA</div>', unsafe_allow_html=True)

# ════════════════════════════
# TAB 6 — KPI SUMMARY
# ════════════════════════════
with t6:
    st.markdown('<div class="section-title">All 5 KPIs — Hackathon Paper Requirements</div>',
                unsafe_allow_html=True)

    cl_tasks = housekeeping[housekeeping["task_type"]=="cleaning"]
    mt_tasks = housekeeping[housekeeping["task_type"]=="maintenance"]
    cl_sla   = round(100*(1-cl_tasks["sla_breached"].mean()),1) if len(cl_tasks) else 0
    mt_sla   = round(100*(1-mt_tasks["sla_breached"].mean()),1) if len(mt_tasks) else 0

    kpi_df = pd.DataFrame({
        "KPI": [
            "KPI 1 — Room Occupancy Rate",
            "KPI 2 — Booking Conversion Efficiency",
            "KPI 3 — Housekeeping SLA (Cleaning)",
            "KPI 3 — Housekeeping SLA (Maintenance)",
            "KPI 4 — RevPAR",
            "KPI 5 — Billing Accuracy Index"
        ],
        "Formula from Paper": [
            "Occupied rooms / Total rooms × 100",
            "(Completed stays / Total reservations) × 100",
            "% cleaning tasks completed ≤ 45 min",
            "% maintenance tasks completed ≤ 120 min",
            "Total revenue / Total available rooms",
            "1 − (billing anomalies / total bills)"
        ],
        "Value": [
            f"{occ_rate}%",
            f"{conv_pct}%",
            f"{cl_sla}%",
            f"{mt_sla}%",
            f"₹{revpar:,.2f}",
            f"{billing_acc:.4f}"
        ],
        "Status": [
            "✅ PASS" if occ_rate>60    else "⚠️ LOW",
            "✅ PASS" if conv_pct>70    else "⚠️ LOW",
            "✅ PASS" if cl_sla>85      else "⚠️ LOW",
            "✅ PASS" if mt_sla>85      else "⚠️ LOW",
            "✅ PASS" if revpar>500     else "⚠️ LOW",
            "✅ PASS" if billing_acc>0.90 else "⚠️ LOW"
        ]
    })
    st.dataframe(kpi_df, use_container_width=True, hide_index=True, height=250)

    st.markdown("<br>", unsafe_allow_html=True)
    g1,g2 = st.columns(2)

    with g1:
        st.markdown('<div class="section-title">KPI 1 — Room Occupancy Gauge</div>', unsafe_allow_html=True)
        fig = go.Figure(go.Indicator(
            mode="gauge+number+delta", value=occ_rate,
            delta={"reference":75},
            gauge={"axis":{"range":[0,100],"tickcolor":"#4a6080"},
                   "bar":{"color":"#00d4ff"},"bgcolor":"#0d1220","bordercolor":"#1e2a45",
                   "steps":[{"range":[0,50],"color":"rgba(239,68,68,0.12)"},
                             {"range":[50,75],"color":"rgba(245,158,11,0.12)"},
                             {"range":[75,100],"color":"rgba(34,197,94,0.12)"}],
                   "threshold":{"line":{"color":"#22c55e","width":2},"thickness":0.75,"value":75}},
            number={"suffix":"%","font":{"color":"#e8f4ff","family":"Syne"}},
            title={"text":"Occupancy Rate","font":{"color":"#4a6080","size":13}}
        ))
        st.plotly_chart(sc(fig,280), use_container_width=True)

    with g2:
        st.markdown('<div class="section-title">KPI 5 — Billing Accuracy Gauge</div>', unsafe_allow_html=True)
        fig2 = go.Figure(go.Indicator(
            mode="gauge+number+delta", value=round(billing_acc*100,2),
            delta={"reference":95},
            gauge={"axis":{"range":[80,100],"tickcolor":"#4a6080"},
                   "bar":{"color":"#7c3aed"},"bgcolor":"#0d1220","bordercolor":"#1e2a45",
                   "steps":[{"range":[80,90],"color":"rgba(239,68,68,0.12)"},
                             {"range":[90,95],"color":"rgba(245,158,11,0.12)"},
                             {"range":[95,100],"color":"rgba(34,197,94,0.12)"}],
                   "threshold":{"line":{"color":"#22c55e","width":2},"thickness":0.75,"value":95}},
            number={"suffix":"%","font":{"color":"#e8f4ff","family":"Syne"}},
            title={"text":"Billing Accuracy Index","font":{"color":"#4a6080","size":13}}
        ))
        st.plotly_chart(sc(fig2,280), use_container_width=True)

# ── Footer ────────────────────────────────────────────────────────────────────
st.markdown("---")
st.markdown("""<div style='text-align:center;color:#2a3a55;font-size:0.68rem;
    letter-spacing:1.5px;text-transform:uppercase;padding:10px 0;'>
    StaySphere Hotel Analytics · Snowflake Medallion Architecture ·
    Bronze → Silver → Gold · Hackathon 2024
</div>""", unsafe_allow_html=True)
