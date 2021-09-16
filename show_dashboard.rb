require "stripe"
require "dotenv"
require "pry"
require "active_support"
require "active_support/core_ext"
require "sinatra"
require "sinatra/reloader"
Dotenv.load

Stripe.api_key = ENV["STRIPE_SECRET_KEY"]
Stripe.api_version = "2019-09-09"
APP_HOST = ENV.fetch("APP_HOST")
STRIPE_CUSTOMER_ID = ENV["STRIPE_CUSTOMER_ID"]
STRIPE_LICENSE_PRODUCT_ID = ENV["STRIPE_LICENSE_PRODUCT_ID"]
STRIPE_SMS_PRODUCT_ID = ENV["STRIPE_SMS_PRODUCT_ID"]
STRIPE_MMS_PRODUCT_ID = ENV["STRIPE_MMS_PRODUCT_ID"]
STRIPE_NUMBER_PRODUCT_ID = ENV["STRIPE_NUMBER_PRODUCT_ID"]
STRIPE_BLOCK_VIEW_PRODUCT_ID = ENV["STRIPE_BLOCK_VIEW_PRODUCT_ID"]

unless defined? STRIPE_JS_HOST
  STRIPE_JS_HOST = "https://js.stripe.com".freeze
end

unless defined? STRIPE_CONNECT_HOST
  STRIPE_CONNECT_HOST = "https://connect.stripe.com".freeze
end

# Checklist
# Create a customer (if needed)
# Create product (if needed)
# Create price (if needed)
# Spin up server to render dashboard
#

if STRIPE_CUSTOMER_ID.blank?
  @customer = Stripe::Customer.create(
    email: "batman@gmail.com",
  )
end

if STRIPE_LICENSE_PRODUCT_ID.blank?
  product =
    Stripe::Product.create(name: "License")
  puts "Created license product #{product.id}"
  STRIPE_LICENSE_PRODUCT_ID = product.id.freeze
end

if STRIPE_SMS_PRODUCT_ID.blank?
  product =
    Stripe::Product.create(name: "Sent SMS")
  puts "Created SMS product #{product.id}"
  STRIPE_SMS_PRODUCT_ID = product.id.freeze
end

if STRIPE_MMS_PRODUCT_ID.blank?
  product =
    Stripe::Product.create(name: "Sent MMS")
  puts "Created MMS product #{product.id}"
  STRIPE_MMS_PRODUCT_ID = product.id.freeze
end

if STRIPE_NUMBER_PRODUCT_ID.blank?
  product =
    Stripe::Product.create(name: "Provisioned Phone Numbers")
  puts "Created number product #{product.id}"
  STRIPE_NUMBER_PRODUCT_ID = product.id.freeze
end

if STRIPE_BLOCK_VIEW_PRODUCT_ID.blank?
  product =
    Stripe::Product.create(name: "Impressions")
  puts "Created impressions product #{product.id}"
  STRIPE_BLOCK_VIEW_PRODUCT_ID = product.id.freeze
end

class StripeDashboardServer < Sinatra::Base
  set :stripe_customer_id, STRIPE_CUSTOMER_ID

  before do
    @subscriptions = Stripe::Subscription.list(customer: settings.stripe_customer_id)
  end

  get "/" do

    puts "We have a visitor!"
    erb :dashboard, locals: {
    }
  end

  post "/customer-portal-link" do
    customer_id = params["customer_id"]
    settings.stripe_customer_id = customer_id

    customer_id = STRIPE_CUSTOMER_ID if customer_id.blank?

    dash_link = Stripe::BillingPortal::Session.create(
      customer: customer_id,
      return_url: APP_HOST,
    )
    redirect dash_link.url
  end

  post "/start-a-subscription" do
    interval = params["interval"]
    text_price = params["text_price"]
    customer_id = params["customer_id"]
    block_view_free = params["block_view_free"]
    block_view_price = params["block_view_price"]
    phone_number_price = params["phone_number_price"]

    text_price = create_price(
      product_id: STRIPE_SMS_PRODUCT_ID,
      unit_amount: text_price,
      interval: interval,
      nickname: "SMS",
      usage_type: "metered",
      free_units: 0,
    )
    number_price = create_price(
      product_id: STRIPE_NUMBER_PRODUCT_ID,
      unit_amount: phone_number_price,
      interval: interval,
      nickname: "Phone Numbers",
      usage_type: "metered",
      free_units: 0,
    )
    block_view_price = create_price(
      product_id: STRIPE_BLOCK_VIEW_PRODUCT_ID,
      unit_amount: block_view_price,
      interval: interval,
      nickname: "Block View",
      usage_type: "metered",
      free_units: block_view_free,
    )

    subscription_params = {
      billing_thresholds: {
        amount_gte: 10_000,
      },
      items: [
        {
          price: block_view_price.id,
        },
        {
          price: text_price.id,
        },
        {
          price: number_price.id,
        },
      ],
    }
    subscription_params.merge(customer: customer_id) if customer_id.present?

    subscription = Stripe::Subscription.create(subscription_params)
    puts "created subscription #{subscription.id}"
    redirect "/"
  end

  post "/create-checkout-session" do
    interval = params["interval"]
    license_amount = params["license_price"]
    text_amount = params["text_price"]
    mms_amount = params["mms_price"]
    phone_number_price = params["phone_number_price"]
    block_view_free = params["block_view_free"]
    block_view_amount = params["block_view_price"]

    license_price = create_price(
      product_id: STRIPE_LICENSE_PRODUCT_ID,
      unit_amount: license_amount,
      interval: interval,
      nickname: "Subscription",
      usage_type: "licensed",
    )
    text_price = create_price(
      product_id: STRIPE_SMS_PRODUCT_ID,
      unit_amount: text_amount,
      interval: interval,
      nickname: "SMS",
      usage_type: "metered",
      free_units: 0,
    )
    mms_price = create_price(
      product_id: STRIPE_MMS_PRODUCT_ID,
      unit_amount: mms_amount,
      interval: interval,
      nickname: "MMS",
      usage_type: "metered",
      free_units: 0,
    )
    number_price = create_price(
      product_id: STRIPE_NUMBER_PRODUCT_ID,
      unit_amount: phone_number_price,
      interval: interval,
      nickname: "Phone Numbers",
      usage_type: "metered",
      free_units: 0,
    )
    block_view_price = create_price(
      product_id: STRIPE_BLOCK_VIEW_PRODUCT_ID,
      unit_amount: block_view_amount,
      interval: interval,
      nickname: "Block View",
      usage_type: "metered",
      free_units: block_view_free,
    )

    session = Stripe::Checkout::Session.create(
      customer: settings.stripe_customer_id,
      success_url: APP_HOST,
      cancel_url: APP_HOST,
      payment_method_types: ["card"],
      mode: "subscription",
      line_items: [
        {
          price: license_price.id,
          quantity: 1,
        },
        {
          price: block_view_price.id,
        },
        {
          price: text_price.id,
        },
        {
          price: mms_price.id,
        },
        {
          price: number_price.id,
        },
      ],
    )
    puts "creating a checkout session"
    redirect session.url
  end

  post "/send-a-text" do
    item_id = params["item_id"]
    event_date = params["event_date"]
    amount = params["amount"]

    amount = 1 if amount.blank?
    event_date = Time.current if event_date.blank?

    usage_record = Stripe::SubscriptionItem.create_usage_record(
      item_id,
      quantity: amount,
      timestamp: event_date.to_i,
      action: "subscription",
    )
    puts "created usage record #{usage_record.id}"
    redirect "/"
  end

  private

  def create_price(product_id:, unit_amount:, interval:, nickname:, usage_type:, free_units:0)
    if usage_type == "metered" && free_units.to_i > 0
      tiers = [
        {
          unit_amount: 0,
          up_to: free_units,
        },
        {
          unit_amount: unit_amount,
          up_to: "inf",
        },
      ]
      Stripe::Price.create(
        product: product_id,
        currency: "usd",
        recurring: {
          interval: interval,
          usage_type: usage_type,
          aggregate_usage: "last_during_period",
        },
        nickname: nickname,
        billing_scheme: "tiered",
        tiers_mode: "graduated",
        tiers: tiers,
      )
    elsif usage_type == "metered" && free_units.to_i.zero?
      Stripe::Price.create(
        product: product_id,
        unit_amount: unit_amount, 
        currency: "usd",
        recurring: {
          interval: interval,
          usage_type: usage_type,
          aggregate_usage: "last_during_period",
        },
        nickname: nickname,
      )
    else
      Stripe::Price.create(
        product: product_id,
        unit_amount: unit_amount,
        currency: "usd",
        recurring: {
          interval: interval,
          usage_type: usage_type,
        },
        nickname: nickname,
      )
    end
  end

end
